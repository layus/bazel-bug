"""Transition rules for the project."""

load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _reset_optimization_transition_impl(settings, attr):
    """Transition that resets optimization_level to default."""
    return {
        "//:optimization_level": "default",
    }

reset_optimization_transition = transition(
    implementation = _reset_optimization_transition_impl,
    inputs = ["//:optimization_level"],
    outputs = ["//:optimization_level"],
)

def _transitioned_cc_library_impl(ctx):
    """Implementation of transitioned_cc_library rule."""
    return cc_common.merge_cc_infos(cc_infos = [
        dep[CcInfo]
        for dep in ctx.attr.deps
    ])

transitioned_cc_library = rule(
    implementation = _transitioned_cc_library_impl,
    attrs = {
        "deps": attr.label_list(
            cfg = reset_optimization_transition,
            providers = [CcInfo],
        ),
    },
)
