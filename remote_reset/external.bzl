

def external_repository_root(label):
    """Get path to repository root from label."""
    return "/".join([
        component
        for component in [label.workspace_root, label.package, label.name]
        if component
    ])


def cp(repository_ctx, src, dest = None):
    """Copy the given file into the external repository root.
    Args:
      repository_ctx: The repository context of the current repository rule.
      src: The source file. Must be a Label if dest is None.
      dest: Optional, The target path within the current repository root.
        By default the relative path to the repository root is preserved.
    Returns:
      The dest value
    """
    if dest == None:
        if type(src) != "Label":
            fail("src must be a Label if dest is not specified explicitly.")
        dest = external_repository_root(src)

    src_path = repository_ctx.path(src)
    dest_path = repository_ctx.path(dest)
    #executable = _is_executable(repository_ctx, src_path)

    # Copy the file
    repository_ctx.file(
        dest_path,
        repository_ctx.read(src_path),
        #executable = executable,
        legacy_utf8 = False,
    )

    return dest


def _impl(repository_ctx):
    #file = repository_ctx.path(repository_ctx.attr.path)
    #print(file)
    text = "FOO"
    for dep in repository_ctx.attr.deps:
        cp(repository_ctx, dep)
    repository_ctx.execute(["sleep", "3"])
    repository_ctx.execute(["echo", "Running repo rule"])
    print("Running print")
    repository_ctx.file("BUILD.bazel", 'exports_files(glob(["*.txt"]))')

external_repo = repository_rule(
    implementation=_impl,
    local=True,
    attrs={
        "path": attr.label(),
        "deps": attr.label_list(),
    },
)

