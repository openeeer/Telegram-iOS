load("@build_bazel_rules_apple//apple:apple.bzl", "apple_dynamic_xcframework_import")

# Prebuilt Phantom proxy engine (gomobile-built dynamic framework).
# Built from github.com/openeeer/phantom_way (package phantom/mobile) via
# `gomobile bind -target=ios`. Exposes PhantommobileStart/Stop/Status/... .
apple_dynamic_xcframework_import(
    name = "Phantom",
    xcframework_imports = glob(["Phantom.xcframework/**"]),
    visibility = ["//visibility:public"],
)
