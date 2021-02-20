genrule(
    name = "authentication_flow_png",
    srcs = ["@plantuml_jar//file", "authentication_flow.plantuml"],
    outs = ["authentication_flow.png"],
    tools = [],
    cmd = " && ".join([
        "TMP=$$(mktemp -d || mktemp -d -t bazel-tmp)",
        "java -jar $(location @plantuml_jar//file) -o $$TMP $(location authentication_flow.plantuml)",
        "mv $$TMP/authentication_flow.png \"$@\""
#        ,"rm -rf $$TMP"
    ])
)
