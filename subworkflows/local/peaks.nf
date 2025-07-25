
include { CALC_GENOME_FRAC
          MACS_BROAD
          MACS_NARROW
          SICER
          CONVERT_SICER
          GEM
          FILTER_GEM
          FRACTION_IN_PEAKS
          CONCAT_FRIPS
          PLOT_FRIP
          JACCARD_INDEX
          CONCAT_JACCARD
          PLOT_JACCARD
          GET_PEAK_META
          CONCAT_PEAK_META
          PLOT_PEAK_WIDTHS    } from "../../modules/local/peaks.nf"
include { BAM_TO_BED          } from "../../modules/local/bedtools.nf"

workflow CALL_PEAKS {
    take:
        chrom_sizes
        chrom_dir
        deduped_tagalign
        deduped_bam
        frag_lengths
        effective_genome_size

    main:
        genome_frac = CALC_GENOME_FRAC(chrom_sizes, effective_genome_size)

        // create channel with [ meta, chip_tag, input_tag, format ]
        deduped_tagalign
            .combine(deduped_tagalign)
            .map {
                meta1, tag1, format1, meta2, tag2, format2 ->
                    meta1.input == meta2.id && format1 == format2 ? [ meta1, tag1, tag2, format1 ]: null
            }
            .set{ ch_tagalign }

        // create macs channel with [ meta, chip_tag, input_tag, format, fraglen, genome_frac]
        ch_tagalign
            .join(frag_lengths)
            .combine(genome_frac)
            .combine(effective_genome_size)
            .set { ch_macs }

        // create sicer channel containing only bed files with [ meta, chip_tag, input_tag, fraglen, genome_frac]
        deduped_tagalign
            .branch{ meta, tag, format ->
                bam: format == 'BAMPE'
                    return(tuple(meta, tag))
                bed: format == 'BED'
                    return(tuple(meta, tag))
            }.set{ tag_split }
        tag_split.bam | BAM_TO_BED
        BAM_TO_BED.out.bed.set{ tag_split_converted }
        tag_split.bed.mix(tag_split_converted).set{ tag_all_bed }
        tag_all_bed
            .combine(tag_all_bed)
            .map {
                meta1, tag1, meta2, tag2 ->
                    meta1.input == meta2.id ? [ meta1, tag1, tag2 ]: null
            }
            .join(frag_lengths)
            .combine(genome_frac)
            .set { ch_sicer }


        // create gem channel with [ meta, chip_tag, input_tag, format, read_dists, chrom_sizes, chrom_dir, effective_genome_sizes ]
        ch_tagalign
            .combine(Channel.fromPath(params.gem_read_dists, checkIfExists: true))
            .combine(chrom_sizes)
            .combine(chrom_dir)
            .combine(effective_genome_size)
            .set { ch_gem }

        ch_peaks = Channel.empty()
        ch_narrow_peaks = Channel.empty()
        if (params.run_macs_broad) {
            ch_macs
                | MACS_BROAD
            MACS_BROAD.out.peak
                | map{ meta, peak, tool ->
                    def meta2 = meta
                    meta2.tool = tool
                    [ meta2, peak, tool ]
                }
                | set{ ch_macs_broad}
            ch_peaks = ch_peaks.mix(ch_macs_broad)
        }
        if (params.run_macs_narrow) {
            ch_macs
                | MACS_NARROW
            MACS_NARROW.out.peak
                | map{ meta, peak, tool ->
                    def meta2 = meta
                    meta2.tool = tool
                    [ meta2, peak, tool ]
                }
                | set{ ch_macs_narrow }
            ch_peaks = ch_peaks.mix(ch_macs_narrow)
            ch_narrow_peaks = ch_narrow_peaks.mix(ch_macs_narrow)
        }
        if (params.run_sicer) {
            ch_sicer | SICER
            SICER.out.peak
                | map{ meta, peak, tool ->
                    def meta2 = meta
                    meta2.tool = tool
                    [ meta2, peak, tool ]
                }
                | CONVERT_SICER
            ch_peaks = ch_peaks.mix(CONVERT_SICER.out.peak)
        }
        if (params.run_gem) {
            ch_gem | GEM
            GEM.out.peak
                | map{ meta, peak, tool ->
                    def meta2 = meta
                    meta2.tool = tool
                    [ meta2, peak, tool ]
                }
                | combine(chrom_sizes)
                | FILTER_GEM
            ch_peaks = ch_peaks.mix(FILTER_GEM.out.peak)
            ch_narrow_peaks = ch_narrow_peaks.mix(FILTER_GEM.out.peak)
        }

        // Create tag align w/ peaks
        tag_all_bed.combine(ch_peaks)
            .map{ it ->
                it.flatten()
            }
            .map{ meta1, tagalign, meta2, peak, tool ->
                meta1.id == meta2.id ? [ meta1, tagalign, peak, tool ] : null
            }
            .set{ ch_tagalign_peaks }
        // Create Channel with meta, deduped bam, peak file, peak-calling tool, and chrom sizes fasta
        deduped_bam.combine(ch_peaks)
            .map{ it ->
               it.flatten()
            }
            .map{  meta1, bam, bai, meta2, peak, tool ->
                meta1.id == meta2.id ? [ meta1, bam, bai, peak, tool ] : null
            }
            .set{ ch_bam_peaks }

        ch_bam_peaks.combine(chrom_sizes) | FRACTION_IN_PEAKS
        FRACTION_IN_PEAKS.out.collect() | CONCAT_FRIPS | PLOT_FRIP

        ch_peaks
            .combine(ch_peaks) // jaccard index on all-vs-all samples & peak-calling tools
            .map{ meta1, peak1, tool1, meta2, peak2, tool2 ->
                (meta1.id != meta2.id || tool1 != tool2) ? [ meta1, peak1, tool1, meta2, peak2, tool2 ] : null
            }
            .combine(chrom_sizes) | JACCARD_INDEX
        JACCARD_INDEX.out.collect() | CONCAT_JACCARD | PLOT_JACCARD

        ch_bam_peaks.combine(chrom_sizes) | GET_PEAK_META
        GET_PEAK_META.out.collect() | CONCAT_PEAK_META | PLOT_PEAK_WIDTHS

        ch_plots = PLOT_FRIP.out
            .mix(PLOT_JACCARD.out)
            .mix(PLOT_PEAK_WIDTHS.out)

    emit:
        peaks = ch_peaks
        narrow_peaks = ch_narrow_peaks
        bam_peaks = ch_bam_peaks
        tagalign_peaks = ch_tagalign_peaks
        plots = ch_plots
}
