using Knit
using Test

HAS_PLOTS = false
try
    @eval using Plots
    global HAS_PLOTS = true
catch
end

@testset "parse_options" begin
    @test Knit.parse_options("") == Dict{Symbol,Any}()
    @test Knit.parse_options("echo=false") == Dict(:echo => false)
    @test Knit.parse_options("eval=true") == Dict(:eval => true)
    @test Knit.parse_options("echo=false, eval=true") == Dict(:echo => false, :eval => true)
    @test Knit.parse_options("results=\"hide\"") == Dict(:results => "hide")
    @test Knit.parse_options("results=hide") == Dict{Symbol,Any}()
end

@testset "parse_chunk_header" begin
    name, opts = Knit.parse_chunk_header("setup")
    @test name == "setup"
    @test opts == Dict{Symbol,Any}()

    name, opts = Knit.parse_chunk_header("stats, echo=false")
    @test name == "stats"
    @test opts == Dict(:echo => false)

    name, opts = Knit.parse_chunk_header("echo=false")
    @test name === nothing
    @test opts == Dict(:echo => false)

    name, opts = Knit.parse_chunk_header("")
    @test name === nothing
    @test opts == Dict{Symbol,Any}()
end

@testset "merge defaults" begin
    opts = merge(Knit.DEFAULT_CHUNK_OPTIONS, Dict(:echo => false))
    @test opts[:echo] == false
    @test opts[:eval] == true
    @test opts[:results] == "markup"
end

@testset "_save_figure" begin
    mktempdir() do dir
        report = Knit.Report(dir, "test_fig")
        # No MIME support — should be no-op
        Knit._save_figure(report, "plain string with no image support")
        @test isempty(report.figures)
        @test report.fignum == 1

        # Plots.Plot — should save a figure via MIME path (not the savefig shortcut)
        if HAS_PLOTS
            p = plot(randn(10))
            Knit._save_figure(report, p)
            @test length(report.figures) == 1
            @test endswith(report.figures[1], ".pdf") || endswith(report.figures[1], ".png")
            @test isfile(joinpath(dir, report.figures[1]))
        end
    end
end
