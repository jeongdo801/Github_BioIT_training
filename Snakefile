import os
import os.path

###############################################################################
 # SETTINGS                                                                    #
 #                                                                             #
 # Set the sample name                                                         #
 #                                                                             #
SAMPLE_NAME = "testSample"
 #                                                                             #
 #                                                                             #
 # By default, the pipeline will expect file to be in a subfolder called       #
 # 'bam' and to be names *.bam and *.bai                                       #
 #                                                                             #
BAMFILE, = glob_wildcards("bam/{cell}.bam")
 #                                                                             #
 #                                                                             #
abbreviate_names = False
 #                                                                             #
 ###############################################################################

configfile: "Snake.config.json"

rule all:
    input:
        expand("result/{s}.tab", s = SAMPLE_NAME),
        expand("result/{s}.npz", s = SAMPLE_NAME),
        expand("result/{s}_sort.txt", s = SAMPLE_NAME),
        expand("result/{s}_sort_num.txt", s = SAMPLE_NAME),
        expand("result/{s}_sort_for_chromVAR.txt", s = SAMPLE_NAME),
        expand("result/{s}_dev_zscore.txt", s = SAMPLE_NAME),
        expand("result/{s}_dev.rda", s = SAMPLE_NAME),
        expand("result/{s}_dev_plot.pdf", s = SAMPLE_NAME)


 #
 # PART I
 # Read preprocessing
 #
	
rule remove_low_quality_reads:
    input:
        bam = "bam/{cell}.bam"
    output:
        bam_pre = "bam/{cell}.sc_pre_mono.bam",
        bam_header = "bam/{cell}.header_test.sam"
    shell:
        """
        module load SAMtools/1.3.1-foss-2016b
		samtools view -H {input} > {output.bam_header} 
		samtools view -F 2304 {input.bam} | awk -f utils/awk_1st.awk | cat {output.bam_header} - | samtools view -Sb - > {output.bam_pre}	
        """

rule sort_bam:
    input:
        "bam/{cell}.sc_pre_mono.bam"
    output:
        "bam/{cell}.sc_pre_mono_sort_for_mark.bam"
    threads:
        2
    shell:
        """
        module load SAMtools/1.3.1-foss-2016b
        samtools sort -@ {threads} -O BAM -o {output} {input}
        """

rule index_num1:
    input:
        "bam/{cell}.sc_pre_mono_sort_for_mark.bam"
    output:
        "bam/{cell}.sc_pre_mono_sort_for_mark.bam.bai"
    shell:
        """
        module load SAMtools/1.3.1-foss-2016b
        samtools index {input}
        """	
	
rule remove_dup:
    input:
        bam="bam/{cell}.sc_pre_mono_sort_for_mark.bam"
    output:
        bam_uniq="bam/{cell}.sc_pre_mono_sort_for_mark_uniq.bam",
        bam_metrix="bam/{cell}.sc_pre_mono.metrix_dup.txt"
    shell:
        """
        module load biobambam2/2.0.76-foss-2016b
		bammarkduplicates markthreads=2 I={input.bam} O={output.bam_uniq} M={output.bam_metrix} index=1 rmdup=1
        """

rule index_num2:
    input:
        "bam/{cell}.sc_pre_mono_sort_for_mark_uniq.bam"
    output:
        "bam/{cell}.sc_pre_mono_sort_for_mark_uniq.bam.bai"
    shell:
        """
        module load SAMtools/1.3.1-foss-2016b
        samtools index {input}
        """

 #
 # PART II
 # Read counting
 #

rule count_reads:
    input:
        bam = expand("bam/{cell}.sc_pre_mono_sort_for_mark_uniq.bam", cell=BAMFILE),
        bai = expand("bam/{cell}.sc_pre_mono_sort_for_mark_uniq.bam.bai", cell=BAMFILE)
    output:
        tab = "result/" + SAMPLE_NAME + ".tab",
        npz = "result/" + SAMPLE_NAME + ".npz",
    shell:
        """
        module load deeptools/2.5.1-foss-2016b-Python-2.7.12
        multiBamSummary BED-file --BED utils/regions_all_hg38_v2_resize_2kb_sort.bed --bamfiles {input.bam} \
            --extendReads --outRawCounts {output.tab} -out {output.npz}
        """


rule count_sort_by_coordinate:
    input:
        "result/" + SAMPLE_NAME + ".tab"
    output:
        "result/" + SAMPLE_NAME + "_sort.txt"
    shell:
        """
        sort -k1,1 -k2,2n -k3,3n -t$'\t' {input} > {output}
        """


rule count_add_peakind:
    input:
        count_sort = "result/" + SAMPLE_NAME + "_sort.txt"
    output:
        "result/" + SAMPLE_NAME + "_sort_num.txt"
    #params:
    #    count_add_peakind = config["count_add_peakind"]
    script:
        "utils/count_add_peakind.snakemake.R"



rule count_sort_by_peakind:
    input:
        "result/" + SAMPLE_NAME + "_sort_num.txt"
    output:
        "result/" + SAMPLE_NAME + "_sort_for_chromVAR.txt"
    shell:
        """
        sort -k1,1n -k2,2n -k3,3n -t$'\t' {input} > {output}
        """


rule zscore_for_motif:
    input:
        count_sort_chromVAR = "result/" + SAMPLE_NAME + "_sort_for_chromVAR.txt",
        DHS_annot = "utils/Result_enh_prom_sort_new_num_sort_for_chromVAR.txt",
        DHS_matrix = "utils/regions_all_hg38_v2_resize_2kb_sort_num_sort_for_chromVAR.bed",
        peakfile = "utils/peak_roadmap_resize_2kb_Enh.bed"
    output:
        dev_zscore = "result/" + SAMPLE_NAME + "_dev_zscore.txt",
        dev = "result/" + SAMPLE_NAME + "_dev.rda",
        dev_plot = "result/" + SAMPLE_NAME + "_dev_plot.pdf"
    params:
        zscore_for_motif = config["zscore_for_motif"]
    shell:
        """
        Rscript {params.zscore_for_motif} {input.count_sort_chromVAR} {input.DHS_annot} {input.DHS_matrix} {input.peakfile} {output.dev_zscore} {output.dev} {output.dev_plot}
        """





