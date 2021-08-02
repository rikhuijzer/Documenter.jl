module HTMLWriterTests

using Test
using Documenter
using Documenter: DocSystem
using Documenter.Writers.HTMLWriter: HTMLWriter, generate_version_file, expand_versions

function verify_version_file(versionfile, entries)
    @test isfile(versionfile)
    content = read(versionfile, String)
    idx = 1
    for entry in entries
        i = findnext(entry, content, idx)
        @test i !== nothing
        idx = last(i)
    end
end

@testset "HTMLWriter" begin
    @test isdir(HTMLWriter.ASSETS)
    @test isdir(HTMLWriter.ASSETS_SASS)
    @test isdir(HTMLWriter.ASSETS_THEMES)

    for theme in HTMLWriter.THEMES
        @test isfile(joinpath(HTMLWriter.ASSETS_SASS, "$(theme).scss"))
        @test isfile(joinpath(HTMLWriter.ASSETS_THEMES, "$(theme).css"))
    end

    # asset handling
    function assetlink(src, asset)
        links = HTMLWriter.asset_links(src, [asset])
        @test length(links) == 1
        (; node = links[1], links[1].attributes...)
    end
    @test_logs (:error, "Absolute path '/foo' passed to asset_links") HTMLWriter.asset_links(
        "/foo", HTMLWriter.HTMLAsset[]
    )
    let asset = asset("https://example.com/foo.js")
        @test asset.uri == "https://example.com/foo.js"
        @test asset.class == :js
        @test asset.islocal === false
        link = assetlink("my/sub/page", asset)
        @test link.node.name === :script
        @test link.src === "https://example.com/foo.js"
    end
    let asset = asset("https://example.com/foo.js", islocal = false)
        @test asset.islocal === false
        link = assetlink("my/sub/page", asset)
        @test link.src === "https://example.com/foo.js"
    end
    let asset = asset("http://example.com/foo.js", class=:ico)
        @test asset.uri == "http://example.com/foo.js"
        @test asset.class == :ico
        @test asset.islocal === false
    end
    let asset = asset("foo/bar.css", islocal=true)
        @test asset.uri == "foo/bar.css"
        @test asset.class == :css
        @test asset.islocal === true
        link = assetlink("my/sub/page", asset)
        @test link.node.name === :link
        @test link.href === "../../foo/bar.css"
        link = assetlink("page.md", asset)
        @test link.href === "foo/bar.css"
        link = assetlink("foo/bar.md", asset)
        @test link.href === "bar.css"
    end
    @test_throws Exception asset("ftp://example.com/foo.js")
    @test_throws Exception asset("example.com/foo.js")
    @test_throws Exception asset("foo.js")
    @test_throws Exception asset("foo.js", islocal = false)
    @test_throws Exception asset("https://example.com/foo.js?q=1")
    @test_throws Exception asset("https://example.com/foo.js", class=:error)
    # Edge cases that do not actually quite work correctly:
    let asset = asset("https://example.com/foo.js", islocal = true)
        @test asset.uri == "https://example.com/foo.js"
        @test asset.islocal === true
        link = assetlink("my/sub/page", asset)
        @test link.node.name === :script
        @test link.src === "../../https:/example.com/foo.js"
    end
    @test_logs (:error, "Absolute URI '/foo/bar.ico' passed to asset") asset("/foo/bar.ico", islocal = true)

    # HTML format object
    @test Documenter.HTML() isa Documenter.HTML
    @test_throws ArgumentError Documenter.HTML(collapselevel=-200)
    @test_throws Exception Documenter.HTML(assets=["foo.js", 10])
    @test_throws ArgumentError Documenter.HTML(footer="foo\n\nbar")
    @test_throws ArgumentError Documenter.HTML(footer="# foo")
    @test_throws ArgumentError Documenter.HTML(footer="")
    @test Documenter.HTML(footer="foo bar [baz](https://github.com)") isa Documenter.HTML

    # MathEngine
    let katex = KaTeX()
        @test length(katex.config) == 1
        @test haskey(katex.config, :delimiters)
    end
    let katex = KaTeX(Dict(:foo => 1))
        @test length(katex.config) == 2
        @test haskey(katex.config, :delimiters)
        @test haskey(katex.config, :foo)
    end
    let katex = KaTeX(Dict(:delimiters => 1, :foo => 2))
        @test length(katex.config) == 2
        @test haskey(katex.config, :delimiters)
        @test katex.config[:delimiters] == 1
        @test haskey(katex.config, :foo)
    end

    let mathjax = MathJax2()
        @test length(mathjax.config) == 5
        @test haskey(mathjax.config, :tex2jax)
        @test haskey(mathjax.config, :config)
        @test haskey(mathjax.config, :jax)
        @test haskey(mathjax.config, :extensions)
        @test haskey(mathjax.config, :TeX)
    end
    let mathjax = MathJax2(Dict(:foo => 1))
        @test length(mathjax.config) == 6
        @test haskey(mathjax.config, :tex2jax)
        @test haskey(mathjax.config, :config)
        @test haskey(mathjax.config, :jax)
        @test haskey(mathjax.config, :extensions)
        @test haskey(mathjax.config, :TeX)
        @test haskey(mathjax.config, :foo)
    end
    let mathjax = MathJax2(Dict(:tex2jax => 1, :foo => 2))
        @test length(mathjax.config) == 6
        @test haskey(mathjax.config, :tex2jax)
        @test haskey(mathjax.config, :config)
        @test haskey(mathjax.config, :jax)
        @test haskey(mathjax.config, :extensions)
        @test haskey(mathjax.config, :TeX)
        @test haskey(mathjax.config, :foo)
        @test mathjax.config[:tex2jax] == 1
    end

    mktempdir() do tmpdir
        versionfile = joinpath(tmpdir, "versions.js")
        versions = ["stable", "dev",
                    "2.1.1", "v2.1.0", "v2.0.1", "v2.0.0",
                    "1.1.1", "v1.1.0", "v1.0.1", "v1.0.0",
                    "0.1.1", "v0.1.0"] # note no `v` on first ones
        cd(tmpdir) do
            for version in versions
                mkdir(version)
            end
        end

        # expanding versions
        versions = ["stable" => "v^", "v#.#", "dev" => "dev"] # default to makedocs
        entries, symlinks = expand_versions(tmpdir, versions)
        @test entries == ["stable", "v2.1", "v2.0", "v1.1", "v1.0", "v0.1", "dev"]
        @test symlinks == ["stable"=>"2.1.1", "v2.1"=>"2.1.1", "v2.0"=>"v2.0.1",
                           "v1.1"=>"1.1.1", "v1.0"=>"v1.0.1", "v0.1"=>"0.1.1",
                           "v2"=>"2.1.1", "v1"=>"1.1.1", "v2.1.1"=>"2.1.1",
                           "v1.1.1"=>"1.1.1", "v0.1.1"=>"0.1.1"]
        generate_version_file(versionfile, entries)
        verify_version_file(versionfile, entries)

        versions = ["v#"]
        entries, symlinks = expand_versions(tmpdir, versions)
        @test entries == ["v2.1", "v1.1"]
        @test symlinks == ["v2.1"=>"2.1.1", "v1.1"=>"1.1.1", "v2"=>"2.1.1", "v1"=>"1.1.1",
                           "v2.0"=>"v2.0.1", "v1.0"=>"v1.0.1", "v0.1"=>"0.1.1",
                           "v2.1.1"=>"2.1.1", "v1.1.1"=>"1.1.1", "v0.1.1"=>"0.1.1"]
        generate_version_file(versionfile, entries)
        verify_version_file(versionfile, entries)

        versions = ["v#.#.#"]
        entries, symlinks = expand_versions(tmpdir, versions)
        @test entries == ["v2.1.1", "v2.1.0", "v2.0.1", "v2.0.0", "v1.1.1", "v1.1.0",
                          "v1.0.1", "v1.0.0", "v0.1.1", "v0.1.0"]
        @test symlinks == ["v2.1.1"=>"2.1.1", "v1.1.1"=>"1.1.1", "v0.1.1"=>"0.1.1",
                           "v2"=>"2.1.1", "v1"=>"1.1.1", "v2.1"=>"2.1.1",
                           "v2.0"=>"v2.0.1", "v1.1"=>"1.1.1", "v1.0"=>"v1.0.1", "v0.1"=>"0.1.1"]
        generate_version_file(versionfile, entries)
        verify_version_file(versionfile, entries)

        versions = ["v^", "devel" => "dev", "foobar", "foo" => "bar"]
        entries, symlinks = @test_logs(
            (:warn, "no match for `versions` entry `\"foobar\"`"),
            (:warn, "no match for `versions` entry `\"foo\" => \"bar\"`"),
            expand_versions(tmpdir, versions)
        )
        @test entries == ["v2.1", "devel"]
        @test ("v2.1" => "2.1.1") in symlinks
        @test ("devel" => "dev") in symlinks
        generate_version_file(versionfile, entries)
        verify_version_file(versionfile, entries)

        versions = ["stable" => "v^", "dev" => "stable"]
        @test_throws ArgumentError expand_versions(tmpdir, versions)
    end

    # Exhaustive Conversion from Markdown to Nodes.
    @testset "MD2Node" begin
        for mod in Base.Docs.modules
            for (binding, multidoc) in DocSystem.getmeta(mod)
                for (typesig, docstr) in multidoc.docs
                    md = Documenter.DocSystem.parsedoc(docstr)
                    @test string(HTMLWriter.mdconvert(md; footnotes=[])) isa String
                end
            end
        end
    end

    @testset "Dollar escapes" begin
        @test string(HTMLWriter.mdconvert("\$1")) == "\$1"
        @test string(HTMLWriter.mdconvert("\$")) == "<span>\$</span>"
    end
end
end
