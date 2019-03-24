rule download_snpeff:
    output: "SnpEff/snpEff.jar"
    shell:
        "git clone --depth=1 https://github.com/smith-chem-wisc/SnpEff"
        "cd SnpEff"
        "mvn install:install-file -Dfile=lib/antlr-4.5.1-complete.jar -DgroupId=org.antlr -DartifactId=antlr -Dversion=4.5.1 -Dpackaging=jar"
        "mvn install:install-file -Dfile=lib/biojava3-core-3.0.7.jar -DgroupId=org.biojava -DartifactId=biojava3-core -Dversion=3.0.7 -Dpackaging=jar"
        "mvn install:install-file -Dfile=lib/biojava3-structure-3.0.7.jar -DgroupId=org.biojava -DartifactId=biojava3-structure -Dversion=3.0.7 -Dpackaging=jar"
        "export VERSION=4.3"
        "export VERSION_UND=`echo $VERSION | tr '.' '_'`"
        "mvn clean compile assembly:assembly"
        "mvn install:install-file -Dfile=target/SnpEff-$VERSION.jar -DgroupId=org.snpeff -DartifactId=SnpEff -Dversion=$VERSION -Dpackaging=jar -DgeneratePom=true --quiet"
        "cp target/SnpEff-$VERSION-jar-with-dependencies.jar snpEff.jar"

rule index_fa:
    input: "ensembl/202122.fa"
    output: "ensembl/202122.fa.fai"
    shell: "samtools faidx ensembl/202122.fa"

rule dict_fa:
    input: "ensembl/202122.fa"
    output: "ensembl/202122.dict"
    shell: "gatk CreateSequenceDictionary -R {input} -O {output}"

# Checks if quality encoding is correct, and then splits n cigar reads
rule split_n_cigar_reads:
    input:
        bam="TestData/mapper0.bam",
        fa="ensembl/202122.fa",
        fai="ensembl/202122.fa.fai",
        fadict="ensembl/202122.dict"
    output:
        fixed=temp("TestData/mapper0.fixedQuals.bam"),
        split="TestData/mapper0.split.bam"
    threads: 1
    shell:
        "gatk FixMisencodedBaseQualityReads -I {input.bam} -O {output.fixed}; gatk SplitNCigarReads -R {input.fa} -I {output.fixed} -O {output.split} || "
        "gatk SplitNCigarReads -R {input.fa} -I {input.bam} -O {output.split};"
        "samtools index {output.split}"

rule base_recalibration:
    input:
        knownsites="ensembl/common_all_20170710.ensembl.vcf",
        knownsitesidx="ensembl/common_all_20170710.ensembl.vcf.idx",
        fa="ensembl/202122.fa",
        bam="TestData/mapper0.split.bam"
    output:
        recaltable="TestData/mapper0.split.recaltable",
        recalbam="TestData/mapper0.split.recal.bam"
    threads: 1
    shell:
        "gatk BaseRecalibrator -R {input.fa} -I {input.bam} --known-sites {input.knownsites} -O {output.recaltable}"
        "gatk ApplyBQSR -R {input.fa} -I {input.bam} --bqsr-recal-file {output.recaltable} -O {output.recalbam}"
        "samtools index {output.recalbam}"

rule call_gvcf_varaints:
    input:
        knownsites="ensembl/common_all_20170710.ensembl.vcf",
        knownsitesidx="ensembl/common_all_20170710.ensembl.vcf.idx",
        fa="ensembl/202122.fa",
        bam="TestData/mapper0.split.recal.bam"
    output: "TestData/mapper0.split.recal.g.vcf.gz",
    threads: 4
    shell:
        "gatk HaplotypeCaller --native-pair-hmm-threads {threads} -R {input.fa} -I {input.bam}"
        " --min-base-quality-score 20 --dont-use-soft-clipped-bases true --dbsnp {input.knownsites} -O {output}"
        " -ERC GVCF --max-mnp-distance 3"
        "gatk IndexFeatureFile -F {output}"

rule call_vcf_variants:
    input:
        fa="ensembl/202122.fa",
        gvcf="TestData/mapper0.split.recal.g.vcf.gz",
    output: "TestData/mapper0.split.recal.g.gt.vcf"
    shell:
        "gatk GenotypeGVCFs -R {input.fa} -V {input.gvcf} -O {output}"
        "gatk IndexFeatureFile -F {output}"

rule filter_indels:
    input:
        fa="ensembl/202122.fa",
        vcf="TestData/mapper0.split.recal.g.gt.vcf"
    output:
        "TestData/mapper0.split.recal.g.gt.NoIndels.vcf"
    shell:
        "gatk SelectVariants --select-type-to-exclude INDEL -R {input.fa} -V {input.vcf} -O {output}"
        "gatk IndexFeatureFile -F {output}"

rule snpeff_databases:
    input: "SnpEff/snpEff.jar"
    output: "snpEffDatabases.txt"
    shell: "java -Xmx2000M -jar {input} databases > {output}"

rule variant_annotation:
    input:
        fa="ensembl/202122.fa",
        vcf="TestData/mapper0.split.recal.g.gt.vcf",
        snpeff="SnpEff/snpEff.jar"
    output:
        ann="TestData/mapper0.split.recal.g.gt.snpeff.vcf",
        html="TestData/mapper0.split.recal.g.gt.snpeff.html",
        genesummary="TestData/mapper0.split.recal.g.gt.snpeff.genes.txt",
        protfa="TestData/mapper0.split.recal.g.gt.snpeff.protein.fasta",
        protxml="TestData/mapper0.split.recal.g.gt.snpeff.protein.xml",
    shell:
        "mkdir SnpEff/data"
        "java -Xmx2000M -jar {input.snpeff} -v -stats {output.html} -fastaProt {output.protfa} -xmlProt {output.protxml} -"
