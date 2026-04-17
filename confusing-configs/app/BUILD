"""Application build file with transitioned library dependency."""

load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("//:transitions.bzl", "transitioned_cc_library")

# Transitioned wrapper around the library that resets the flag to default
transitioned_cc_library(
    name = "lib_transitioned",
    deps = ["//lib"],
)

# Binary target using both transitioned and normal library
cc_binary(
    name = "myapp",
    srcs = ["main.cpp"],
    visibility = ["//visibility:public"],
    deps = [
        ":lib_transitioned",
        "//lib",
    ],
)
