
def _dump_env(ctx):
    val = ctx.os.environ.get("FOO", "nothing")
    print("FOO", val)
    ctx.file("FOO", val)


dump_env = repository_rule(
    implementation = _dump_env,
    local = True,
)

