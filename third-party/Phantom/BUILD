load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_xcframework_import")

# Phantom proxy engine, STATIC library xcframework.
#
# The Phantom.xcframework directory is generated at CI time (before bazel runs)
# from github.com/openeeer/phantom_way (cmd/phantomcbridge) via
# `go build -buildmode=c-archive` + `xcodebuild -create-xcframework`. See the
# "Build Phantom static xcframework" step in /codemagic.yaml.
#
# Static linking is used deliberately: a Go-built dynamic framework cannot be
# processed by rules_apple's imported_dynamic_framework_processor (its
# `bitcode_strip` step crashes on Go's Mach-O layout). A static library is
# linked directly into the app binary and avoids that path entirely.
apple_static_xcframework_import(
    name = "Phantom",
    xcframework_imports = glob(["Phantom.xcframework/**"]),
    visibility = ["//visibility:public"],
)
