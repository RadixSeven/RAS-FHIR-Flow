def plantuml_png(name, src, **kwargs):
    """Create a png from a plantuml file"""
    out_name = src.replace('.plantuml', '.png')
    native.genrule(
        name = name,
        srcs = ["@plantuml_jar//file", src],
        outs = [out_name],
        tools = [],
        cmd = " && ".join([
            "TMP=$$(mktemp -d || mktemp -d -t bazel-tmp)",
            "java -jar $(location @plantuml_jar//file) -o $$TMP $(location " + src + ")",
            "mv $$TMP/" + out_name + " \"$@\"",
            "rm -rf $$TMP"
        ],
        **kwargs
        )
    )
