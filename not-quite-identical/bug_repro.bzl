"""Inlined rules/transitions/providers for duplicate-paths bug reproduction."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def require_cc_implementations(names):
    """Return list of //impl:_impl_<name> labels."""
    return ["//impl:_impl_%s" % n for n in names]

CcLibraryGroupInfo = provider(fields = None)
CcLinkTimeDepsInfo = provider(fields = ["deps"])

# --- Settings used by transitions ---
APP_NAME_SETTING = "//:app_name"
LIB_SET_SETTING = "//:lib_set"
VARIANT_SETTING = "//:variant"
PLATFORM_SETTING = "//command_line_option:platforms"
# --- Defaults ---
APP_NAME_SETTING_DEFAULT = "app"
LIB_SET_SETTING_DEFAULT = "//:variant_a_lib_set"
VARIANT_SETTING_DEFAULT = "x1"
PLATFORM_SETTING_DEFAULT = "//:target_platform_x86_64"

# --- variant_outputs_transition: creates one of the two colliding configs ---
def _variant_outputs_transition_impl(settings, attr):
    return {
        "//command_line_option:compilation_mode": attr.opt,
        APP_NAME_SETTING: attr.app_name,
        LIB_SET_SETTING: attr.lib_set,
        VARIANT_SETTING: attr.variant_name,
        PLATFORM_SETTING: str(attr.platform),
    }

variant_outputs_transition = transition(
    implementation = _variant_outputs_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:compilation_mode",
        APP_NAME_SETTING,
        LIB_SET_SETTING,
        VARIANT_SETTING,
        PLATFORM_SETTING,
    ],
)

# --- reset_configuration_default: creates the OTHER colliding config ---
# Same flag values as variant_outputs_transition but reached via a different
# transition path, hence different ST hash.
CONFIGURATION_SETTINGS_DEFAULT = {
    "//command_line_option:compilation_mode": "opt",
    APP_NAME_SETTING: APP_NAME_SETTING_DEFAULT,
    LIB_SET_SETTING: LIB_SET_SETTING_DEFAULT,
    VARIANT_SETTING: VARIANT_SETTING_DEFAULT,
    PLATFORM_SETTING: PLATFORM_SETTING_DEFAULT,
}

reset_configuration_default = transition(
    implementation = lambda settings, attr: CONFIGURATION_SETTINGS_DEFAULT,
    inputs = [],
    outputs = CONFIGURATION_SETTINGS_DEFAULT.keys(),
)

# --- apply_variant_transition rule ---
def _apply_variant_transition_impl(ctx):
    info = ctx.attr.srcs[0][DefaultInfo] if type(ctx.attr.srcs) == type([]) else ctx.attr.srcs[DefaultInfo]
    return DefaultInfo(files = info.files)

apply_variant_transition = rule(
    implementation = _apply_variant_transition_impl,
    attrs = {
        "srcs": attr.label(mandatory = True, cfg = variant_outputs_transition),
        "platform": attr.label(mandatory = True),
        "lib_set": attr.label(mandatory = True),
        "app_name": attr.string(default = APP_NAME_SETTING_DEFAULT),
        "opt": attr.string(default = "opt"),
        "variant_name": attr.string(mandatory = True),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

# --- cc_reset_transition: resets lib_set/variant to defaults ---
_CC_RESET_DEFAULT_CONFIG = {
    LIB_SET_SETTING: LIB_SET_SETTING_DEFAULT,
    VARIANT_SETTING: VARIANT_SETTING_DEFAULT,
}

cc_reset_transition = transition(
    inputs = [],
    outputs = [LIB_SET_SETTING, VARIANT_SETTING],
    implementation = lambda settings, attr: _CC_RESET_DEFAULT_CONFIG,
)

# --- create_cc_lib_set: groups cc_libraries under cc_reset_transition ---
def _create_cc_lib_set_impl(ctx):
    lib_group = {lib.label.name: lib[CcInfo] for lib in ctx.attr.libs}
    return [CcLibraryGroupInfo(**lib_group)]

create_cc_lib_set = rule(
    implementation = _create_cc_lib_set_impl,
    cfg = cc_reset_transition,
    attrs = {
        "libs": attr.label_list(mandatory = True, providers = [CcInfo]),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

# --- convert_cc_link_deps_into_ccinfo: second config path for the test ---
def _convert_cc_link_deps_into_ccinfo_impl(ctx):
    providers = [dep[CcLinkTimeDepsInfo] for dep in ctx.attr.deps if CcLinkTimeDepsInfo in dep]
    cc_depsets = [prov.deps for prov in providers]
    cc_list = depset(transitive = cc_depsets).to_list()
    return cc_common.merge_cc_infos(direct_cc_infos = cc_list)

convert_cc_link_deps_into_ccinfo = rule(
    cfg = cc_reset_transition,
    implementation = _convert_cc_link_deps_into_ccinfo_impl,
    attrs = {
        "deps": attr.label_list(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    provides = [CcInfo],
)

# --- cc_forward_providers: merges CcInfo and CcLinkTimeDepsInfo ---
def _cc_forward_providers_impl(ctx):
    return [
        ctx.attr.target[DefaultInfo],
        ctx.attr.target[CcInfo],
        ctx.attr.link_dep[CcLinkTimeDepsInfo],
    ]

cc_forward_providers = rule(
    implementation = _cc_forward_providers_impl,
    attrs = {
        "target": attr.label(providers = [CcInfo]),
        "link_dep": attr.label(providers = [CcLinkTimeDepsInfo]),
    },
    provides = [CcInfo, CcLinkTimeDepsInfo],
)

# --- cc_extract_link_deps_provider ---
def _cc_extract_link_deps_provider_impl(ctx):
    providers = [dep[CcLinkTimeDepsInfo] for dep in ctx.attr.deps if CcLinkTimeDepsInfo in dep]
    deps_providers = [dep[CcLinkTimeDepsInfo] for dep in ctx.attr.link_deps]
    transitive = [obj.deps for obj in providers + deps_providers]
    return CcLinkTimeDepsInfo(deps = depset(transitive = transitive))

cc_extract_link_deps_provider = rule(
    implementation = _cc_extract_link_deps_provider_impl,
    attrs = {
        "deps": attr.label_list(),
        "link_deps": attr.label_list(providers = [CcLinkTimeDepsInfo]),
    },
    provides = [CcLinkTimeDepsInfo],
)

# --- cc_retrieve_link_deps / cc_resolve_lib_set: resolve lib_names ---
def _cc_retrieve_link_deps_impl(ctx):
    group_providers = [dep[CcLibraryGroupInfo] for dep in ctx.attr.deps]
    resolved_libs = []
    for name in ctx.attr.lib_names:
        for group_provider in group_providers:
            if hasattr(group_provider, name):
                resolved_libs.append(getattr(group_provider, name))
    return CcLinkTimeDepsInfo(deps = depset(resolved_libs))

cc_retrieve_link_deps = rule(
    implementation = _cc_retrieve_link_deps_impl,
    attrs = {
        "deps": attr.label_list(providers = [CcLibraryGroupInfo]),
        "lib_names": attr.string_list(),
    },
    provides = [CcLinkTimeDepsInfo],
)

def _cc_resolve_lib_set_impl(ctx):
    default = ctx.attr._default[CcInfo]
    lib_group_provider = ctx.attr._library_group[CcLibraryGroupInfo]
    resolved_libs = []
    for name in ctx.attr.lib_names:
        resolved_libs.append(
            getattr(lib_group_provider, name) if hasattr(lib_group_provider, name) else default,
        )
    return CcLinkTimeDepsInfo(deps = depset(resolved_libs))

cc_resolve_lib_set = rule(
    implementation = _cc_resolve_lib_set_impl,
    attrs = {
        "lib_names": attr.string_list(),
        "_library_group": attr.label(default = "//:lib_set"),
        "_default": attr.label(default = "//:empty", providers = [CcInfo]),
    },
    provides = [CcLinkTimeDepsInfo],
)

# --- stub autogenerators (cfg=reset_configuration_default creates the
#     second configuration that collides with variant_outputs_transition) ---
def _stub_autogen_impl(ctx):
    headers = []
    data = []
    for name in ctx.attr.output_names:
        _, ext = paths.split_extension(name)
        if ext == ".h":
            f = ctx.actions.declare_file(paths.join("public_include/autogen", name))
            headers.append(f)
        else:
            f = ctx.actions.declare_file(name)
            data.append(f)
        ctx.actions.write(output = f, content = "// stub autogen\n")

    return [
        CcInfo(compilation_context = cc_common.create_compilation_context(
            headers = depset(headers),
            quote_includes = depset(
                [paths.dirname(h.path) for h in headers] +
                [paths.join(paths.dirname(h.root.path), "bin") for h in headers],
            ),
        )),
        DefaultInfo(files = depset(headers + data)),
    ]

_stub_autogen = rule(
    implementation = _stub_autogen_impl,
    attrs = {
        "inputs": attr.label_list(allow_files = True),
        "output_names": attr.string_list(mandatory = True),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    cfg = reset_configuration_default,
)

def gen_defs(name, product_definition):
    _stub_autogen(
        name = name,
        inputs = product_definition,
        output_names = ["defs.h"],
        tags = ["manual"],
    )

def yaml_generator(name, tag, targets, visibility = None):
    _stub_autogen(
        name = name,
        inputs = targets,
        output_names = ["config_{}.yaml".format(tag)],
        tags = ["manual"],
        visibility = visibility,
    )

def stub_proto_converter(name, inputs = [], visibility = None):
    """Stub replacement. Uses cfg=reset_configuration_default."""
    _stub_autogen(
        name = name,
        inputs = inputs,
        output_names = ["proto_dummy.h"],
        tags = ["manual"],
        visibility = visibility,
    )

def _export_autogen_headers_impl(ctx):
    outputs = []
    for header in ctx.files.headers:
        output = ctx.actions.declare_file(paths.join("public_include/autogen", paths.basename(header.path)))
        ctx.actions.symlink(output = output, target_file = header)
        outputs.append(output)
    return DefaultInfo(files = depset(outputs))

export_autogen_headers = rule(
    implementation = _export_autogen_headers_impl,
    attrs = {
        "headers": attr.label_list(mandatory = True, allow_files = [".h"]),
    },
)
