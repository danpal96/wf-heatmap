process joinTables {
    publishDir params.out_dir, mode: "copy"
    label "miller"

    input:
    path tables

    output:
    path "table.tsv"

    script:
    """
    mlr --tsv put '\$[[1]] = "feature"' \\
        then unsparsify --fill-with 0 \\
        then stats1 -a sum -g feature --fx '^feature\$' \\
        then rename -r '_sum\$,' ${tables} > table.tsv
    """
}

process makeParamsJSON {
    publishDir params.out_dir, mode: "copy"

    input:
    val parameters

    output:
    path "params.json"

    exec:
    def json = groovy.json.JsonOutput.toJson(parameters)
    def json_pretty = groovy.json.JsonOutput.prettyPrint(json)
    file("${task.workDir}/params.json").text = json_pretty
}

process makeReport {
    publishDir params.out_dir, mode: "copy"
    label "r_env"

    input:
    path table
    path sample_metadata
    path feature_metadata
    path params_json

    output:
    path "wf-heatmap-report.html"
    path "heatmap"

    script:
    """
    #!/usr/bin/env Rscript

    library(htmltools)
    library(htmlwidgets)
    library(heatmaply)
    library(jsonlite)

    params = read_json("params.json")

    data <- read.csv("${table}", sep="\t", check.names = FALSE, row.names = 1) |> as.matrix()
    if (!is.null(params\$sample_metadata)) {
        sample_metadata <- read.csv("${sample_metadata}", sep="\t", check.names = FALSE, row.names="sample")
        sel_cols <- row.names(sample_metadata)
        data <- data[,sel_cols]
    } else {
        sample_metadata <- NULL
    }
    if (!is.null(params\$feature_metadata)) {
        feature_metadata <- read.csv("${feature_metadata}", sep="\t", check.names = FALSE, row.names="feature")
        sel_rows <- row.names(feature_metadata)
        data <- data[sel_rows,]
    } else {
        feature_metadata <- NULL
    }

    fig <- heatmaply(
        data,
        col_side_colors=sample_metadata,
        row_side_colors=feature_metadata,
        Rowv=params\$rows_dendrogram,
        Colv=params\$columns_dendrogram
    )
    fig <- config(fig, toImageButtonOptions = list(format= 'svg'))
    dir.create("heatmap", showWarnings = FALSE)
    saveWidget(fig, "heatmap/heatmap.html", selfcontained = FALSE, , libdir = "lib")
    page = tagList(
        h1("Report"),
        div(
            tags\$iframe(
                src="heatmap/heatmap.html",
                frameBorder = "0",
                width="99%",
                height="99%",
                style=css(flex="1")
            ),
            style=css(resize="both", overflow="auto", display="flex", height="1000px", border="1px solid black")
        )
    )
    save_html(page, "wf-heatmap-report.html")
    """
}

workflow {
    WorkflowMain.initialise(workflow, params, log)

    table = file(params.table, checkIfExists: true)
    if (table.isDirectory()) {
        def tables = files("${params.table}/*.tsv", checkIfExists: true)
        table = joinTables(tables)
    }
    sample_metadata = params.sample_metadata == null ? file("${projectDir}/assets/NO_SAMPLE_FILE") : file(params.sample_metadata, checkIfExists: true)
    feature_metadata = params.feature_metadata == null ? file("${projectDir}/assets/NO_FEATURE_FILE") : file(params.feature_metadata, checkIfExists: true)

    makeParamsJSON(params)

    makeReport(table, sample_metadata, feature_metadata, makeParamsJSON.out)
}
