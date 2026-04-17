def _repo_fail(repository_ctx):
    verbose = repository_ctx.attr.verbose
    result = repository_ctx.execute(['bash', '-c', 'seq 1 11 >&2 && false'], quiet = not verbose)
    if result.return_code:
        outputs = dict(
            failure_message = 'Some custom failure message',
            return_code = result.return_code,
            stderr = '      > '.join(('\n'+result.stderr).splitlines(True)),
        )
        if not verbose:
            fail("Simpler")
        else:
            fail("""
  {failure_message}
    Return code: {return_code}
    Error output: {stderr}
""".format(**outputs))

    return result

repo_fail = repository_rule(
    implementation = _repo_fail,
    local = True,
    attrs = {
        "verbose": attr.bool(mandatory = True),
    },
)
