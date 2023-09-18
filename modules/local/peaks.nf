
process CALC_GENOME_FRAC {
    label 'peaks'

    container = "${params.containers.base}"

    input:
        path(chrom_sizes)

    output:
        env(genome_frac), emit: genome_frac

    script:
    """
    genome_frac=`calc_effective_genome_fraction.py ${params.genomes[ params.genome ].effective_genome_size} ${chrom_sizes} ${params.deeptools.excluded_chroms}`
    echo \$genome_frac
    """

    stub:
    """
    genome_frac=0.75
    echo \$genome_frac
    """
}


process MACS_BROAD {
    tag { meta.id }
    label 'peaks'

    container = "${params.containers.macs2}"

    input:
        tuple val(meta), path(chip), path(input), val(fraglen), val(genome_frac)

    output:
        path("${meta.id}_peaks.xls")
        path("${meta.id}_peaks.broadPeak"), emit: broad_peak
        path("${meta.id}_peaks.gappedPeak")

    script:
    """
    macs2 callpeak \\
      -t ${chip} \\
      -c ${input} \\
      -g ${params.genomes[ params.genome ].effective_genome_size} \\
      -n ${meta.id} \\
      --extsize ${fraglen} \\
      --nomodel \\
      -q 0.01 \\
      --keep-dup='all' \\
      --broad \\
      --broad-cutoff 0.01
    """

    stub:
    """
    for ext in xls broadPeak gappedPeak; do
        touch ${meta.id}_peaks.\${ext}
    done
    """

}

process MACS_NARROW {
    tag { meta.id }
    label 'peaks'

    container = "${params.containers.macs2}"

    input:
        tuple val(meta), path(chip), path(input), val(fraglen), val(genome_frac)

    output:
        path("${meta.id}_peaks.xls")
        path("${meta.id}_peaks.narrowPeak"), emit: narrow_peak
        path("${meta.id}_summits.bed")

    script:
    """
    macs2 callpeak \\
      -t ${chip} \\
      -c ${input} \\
      -g ${params.genomes[ params.genome ].effective_genome_size} \\
      -n ${meta.id} \\
      --extsize ${fraglen} \\
      --nomodel \\
      -q 0.01 \\
      --keep-dup='all'
    """

    stub:
    """
    for ext in peaks.xls peaks.narrowPeak summits.bed; do
        touch ${meta.id}_\${ext}
    done
    """
}

process SICER {
    tag { meta.id }
    label 'peaks'
    label 'process_high'

    container = "${params.containers.sicer}"

    input:
        tuple val(meta), path(chip), path(input), val(fraglen), val(genome_frac)

    output:
        tuple path("*.scoreisland"), path("*normalized.wig"), path("*islands-summary"), path("*island.bed")

    script:
    """
    sicer \\
      -t ${chip} \\
      -c ${input} \\
      -s ${params.genome} \\
      -rt 100 \\
      -w 300 \\
      -f ${fraglen} \\
      -egf ${genome_frac} \\
      -g 600 \\
      -fdr 1E-2 \\
      -cpu ${task.cpus}
    """

    stub:
    """
    for ext in scoreisland normalized.wig islands-summary island.bed; do
        touch ${meta.id}.\${ext}
    done
    """
}
/*
process SICER_NO_CTRL { // TODO just use one process for each peak caller with optional ctrl input
    script:
    """
    sicer \\
      -t ${chip} \\
      -s ${params.genome} \\
      -rt 100 \\
      -w 300 \\
      -f ${fraglen} \\
      -egf ${genome_frac} \\
      -g 600 \\
      -e 100 \\
      -cpu ${task.cpus}
    """
}
*/
process GEM {
    tag { meta.id }
    label 'peaks'
    label 'process_high'

    container = "${params.containers.gem}"

    input:
        tuple val(meta), path(chip), path(input), path(read_dists), path(chrom_sizes)
        path(chrom_files)

    output:
        path("${meta.id}/*.GEM_events.txt"), emit: events

    script:
    // $GEMJAR is defined in the docker container
    """
    java -Xmx30g -jar \$GEMJAR \\
      --t ${task.cpus} \\
      --d ${read_dists} \\
      --g ${chrom_sizes} \\
      --genome ${chrom_files} \\
      --expt ${chip} \\
      --ctrl ${input} \\
      --out ${meta.id} \\
      --k_min 6 \\
      --k_max 13 \\
      --outNP \\
      --nrf
    """

    stub:
    """
    mkdir ${meta.id}
    touch ${meta.id}/${meta.id}.GEM_events.txt
    """
}