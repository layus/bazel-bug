# MWE showcasing the verbosity of repository_rule failures

This is an investigation into bazel and `rules_nixpkgs`, to understand why `nix-build` errors from `nixpkgs_package()` repository rule are printed four (!) times in bazel output.

It turns out that they are printed
1. As part of `repository_ctx.execute(..., quiet = False)`,
2. As a repository fetch failure,
3. As a WORKSPACE rule evaluation failure,
4. As the final, fatal error that stopped bazel.

When these errors are but a bit verbose, it makes bazel output very hard to parse.

`An error occurred during the fetch of repository XXX` is defined here:
https://github.com/bazelbuild/bazel/blob/7.0.0-pre.20230123.5/src/main/java/com/google/devtools/build/lib/bazel/repository/starlark/StarlarkRepositoryFunction.java#L267-L273
It is followed (in the code) by the `INFO: Repository XXX instantiated at: ...` message, even though the message seems to be printed first in the output.

```java
/* src/main/java/com/google/devtools/build/lib/bazel/repository/starlark/StarlarkRepositoryFunction.java#L267-L275 */
      env.getListener()
          .handle(
              Event.error(
                  "An error occurred during the fetch of repository '"
                      + rule.getName()
                      + "':\n   "
                      + e.getMessageWithStack()));
      env.getListener()
          .handle(Event.info(RepositoryResolvedEvent.getRuleDefinitionInformation(rule)));
```

The `ERROR: WORKSPACE:<line>:<column>: fetching repo_fail rule <label>:` comes from
https://github.com/bazelbuild/bazel/blob/7.0.0-pre.20230123.5/src/main/java/com/google/devtools/build/lib/rules/repository/RepositoryDelegatorFunction.java#L416-L419 where it is wrapped in an `AlreadyReportedRepositoryAccessException` to avoid further reporting this error. See a bit below the above snippet.

```java
/* src/main/java/com/google/devtools/build/lib/rules/repository/RepositoryDelegatorFunction.java#L416-L419 */

      env.getListener()
          .handle(
              Event.error(
                  rule.getLocation(), String.format("fetching %s: %s", rule, e.getMessage())));

      // Rewrap the underlying exception to signal callers not to re-report this error.
      throw new RepositoryFunctionException(
          new AlreadyReportedRepositoryAccessException(e.getCause()),
          e.isTransient() ? Transience.TRANSIENT : Transience.PERSISTENT);
    }
```

Finally, that final error is printed by the bazel command. I cannot say where or how exactly because this happens in the bazel command itself, not in the daemon, and is not tracked by `--host_jvm_debug`.

My point here is that reporting the error three times makes it unsuitable for long debug messages. But there is no other place to provide this debug information.

An option could be to improve the `quite = False` output to add color. But that output is basically unreadable when multiple repository rules run in parallel. 

Ideally, one of the two Event.error logging would disappear, and the final error printed by bezel would be a bit more terse, like `"Failed to fetch repository rule <label>"` or any simple error message that makes you look at the log to find the details. That way, we get only one instance of the error. Or two if `quiet = False` and people want to get a feeling of what is curently running, util we get https://github.com/bazelbuild/bazel/issues/8655.

## Example 1

A syntax error in the rule definition

``` 
$ bazel build @terse//:'*'
INFO: Repository terse instantiated at:
  /home/layus/projects/bazel-bug/repeated_error/WORKSPACE:3:10: in <toplevel>
Repository rule repo_fail defined at:
  /home/layus/projects/bazel-bug/repeated_error/main.bzl:23:28: in <toplevel>
ERROR: An error occurred during the fetch of repository 'terse':
   Traceback (most recent call last):
	File "/home/layus/projects/bazel-bug/repeated_error/main.bzl", line 3, column 29, in _repo_fail
		verbose = repository_ctx.attrs.verbose
Error: 'repository_ctx' value has no field or method 'attrs' (did you mean 'attr'?)
ERROR: /home/layus/projects/bazel-bug/repeated_error/WORKSPACE:3:10: fetching repo_fail rule //external:terse: Traceback (most recent call last):
	File "/home/layus/projects/bazel-bug/repeated_error/main.bzl", line 3, column 29, in _repo_fail
		verbose = repository_ctx.attrs.verbose
Error: 'repository_ctx' value has no field or method 'attrs' (did you mean 'attr'?)
ERROR: 'repository_ctx' value has no field or method 'attrs' (did you mean 'attr'?)
INFO: Elapsed time: 0.073s
INFO: 0 processes.
FAILED: Build did NOT complete successfully (0 packages loaded)
```

## Example 2

An error purposefuly thrown by the rule.

Note the simmilarity with the above error, everywhere but for the error message itself

```
$ bazel build @terse//:'*'
INFO: Repository terse instantiated at:
  /home/layus/projects/bazel-bug/repeated_error/WORKSPACE:3:10: in <toplevel>
Repository rule repo_fail defined at:
  /home/layus/projects/bazel-bug/repeated_error/main.bzl:23:28: in <toplevel>
ERROR: An error occurred during the fetch of repository 'terse':
   Traceback (most recent call last):
	File "/home/layus/projects/bazel-bug/repeated_error/main.bzl", line 12, column 17, in _repo_fail
		fail("Simpler")
Error in fail: Simpler
ERROR: /home/layus/projects/bazel-bug/repeated_error/WORKSPACE:3:10: fetching repo_fail rule //external:terse: Traceback (most recent call last):
	File "/home/layus/projects/bazel-bug/repeated_error/main.bzl", line 12, column 17, in _repo_fail
		fail("Simpler")
Error in fail: Simpler
ERROR: Simpler
INFO: Elapsed time: 0.067s
INFO: 0 processes.
FAILED: Build did NOT complete successfully (0 packages loaded)
```


## Example 3

An error that tries to be friendly by

* turning `quiet = False` on repository_ctx.execute and
* reproducing the comamnd output in the error message

```
$ bazel build @verbose//:'*'
1
2
3
4
5
6
7
8
9
10
INFO: Repository verbose instantiated at:
  /home/layus/projects/bazel-bug/repeated_error/WORKSPACE:8:10: in <toplevel>
Repository rule repo_fail defined at:
  /home/layus/projects/bazel-bug/repeated_error/main.bzl:23:28: in <toplevel>
ERROR: An error occurred during the fetch of repository 'verbose':
   Traceback (most recent call last):
	File "/home/layus/projects/bazel-bug/repeated_error/main.bzl", line 14, column 17, in _repo_fail
		fail("""
Error in fail: 
Some custom failure message
Return code: 1
Error output:
1
2
3
4
5
6
7
8
9
10

ERROR: /home/layus/projects/bazel-bug/repeated_error/WORKSPACE:8:10: fetching repo_fail rule //external:verbose: Traceback (most recent call last):
	File "/home/layus/projects/bazel-bug/repeated_error/main.bzl", line 14, column 17, in _repo_fail
		fail("""
Error in fail: 
Some custom failure message
Return code: 1
Error output:
1
2
3
4
5
6
7
8
9
10

ERROR: 
Some custom failure message
Return code: 1
Error output:
1
2
3
4
5
6
7
8
9
10

INFO: Elapsed time: 0.033s
INFO: 0 processes.
FAILED: Build did NOT complete successfully (0 packages loaded)
```
