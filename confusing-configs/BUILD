"""Root build file with flag and transition definitions."""

load("@bazel_skylib//rules:common_settings.bzl", "string_flag")

# Declare a custom user flag
string_flag(
    name = "optimization_level",
    build_setting_default = "default",
    visibility = ["//visibility:public"],
)
