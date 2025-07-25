

include { BWA_MEM                } from '../../../modules/CCBR/bwa/mem'
include { SAMTOOLS_FILTERALIGNED } from '../../../modules/CCBR/samtools/filteraligned'
include { SAMTOOLS_COUNT } from '../../../modules/local/samtools/count'
include { PICARD_SAMTOFASTQ      } from '../../../modules/CCBR/picard/samtofastq'
include { CUSTOM_COUNTFASTQ      } from '../../../modules/CCBR/custom/countfastq'

workflow FILTER_BLACKLIST {
    take:
        ch_fastq_input      // channel: [ val(meta), path(fastq) ]
        ch_blacklist_index  // channel: [ val(meta), path(bwa/*) ]

    main:
        ch_versions = Channel.empty()

        BWA_MEM ( ch_fastq_input, ch_blacklist_index )
        SAMTOOLS_COUNT( BWA_MEM.out.bam )
        SAMTOOLS_FILTERALIGNED( BWA_MEM.out.bam )
        PICARD_SAMTOFASTQ( SAMTOOLS_FILTERALIGNED.out.bam )
        CUSTOM_COUNTFASTQ( PICARD_SAMTOFASTQ.out.paired )

        ch_versions = ch_versions.mix(
            BWA_MEM.out.versions,
            SAMTOOLS_FILTERALIGNED.out.versions,
            PICARD_SAMTOFASTQ.out.versions,
            CUSTOM_COUNTFASTQ.out.versions
        )

    emit:
        aligned_bam       = BWA_MEM.out.bam          // channel: [ val(meta), path(bam) ]
        reads             = PICARD_SAMTOFASTQ.out.paired  // channel: [ val(meta), path(fastq) ]
        n_surviving_reads = CUSTOM_COUNTFASTQ.out.count
        n_aligned_reads   = SAMTOOLS_COUNT.out.count
        versions          = ch_versions           // channel: [ path(versions.yml) ]
}
