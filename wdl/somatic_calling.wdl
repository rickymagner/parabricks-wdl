# Copyright 2022 NVIDIA CORPORATION & AFFILIATES
version 1.0

task mutect2_prepon {
    input {
        File ponVCF
        File ponTBI
        String pbPATH
        File pbLicenseBin
        String? pbDocker
        Int nGPU = 4
        String gpuModel = "nvidia-tesla-v100"
        String gpuDriverVersion = "460.73.01"
        Int nThreads = 32
        Int gbRAM = 120
        Int diskGB = 0
        Int runtimeMinutes = 600
        String hpcQueue = "gpu"
        Int maxPreemptAttempts = 3
    }

    Int auto_diskGB = if diskGB == 0 then ceil(size(ponVCF, "GB") * 2) + 50 else diskGB

    String outbase = basename(ponVCF)
    command {
        time ~{pbPATH} prepon --in-pon-file ~{ponVCF}
    }
    output {
        File outputPON = "~{outbase}.pon"
    }
    runtime {
        docker : "~{pbDocker}"
        disks : "local-disk ~{auto_diskGB} SSD"
        cpu : nThreads
        memory : "~{gbRAM} GB"
        hpcMemory : gbRAM
        hpcQueue : "~{hpcQueue}"
        hpcRuntimeMinutes : runtimeMinutes
        gpuType : "~{gpuModel}"
        gpuCount : nGPU
        nvidiaDriverVersion : "~{gpuDriverVersion}"
        zones : ["us-central1-a", "us-central1-b", "us-central1-c"]
        preemptible : maxPreemptAttempts
    }
}

task mutect2_call {
    input {
        File tumorBAM
        File tumorBAI
        String tumorName
        File normalBAM
        File normalBAI
        String normalName
        File inputRefTarball
        String pbPATH
        File pbLicenseBin
        File? ponFile
        File? ponVCF
        File? ponTBI
        String? pbDocker
        Int nGPU = 4
        String gpuModel = "nvidia-tesla-v100"
        String gpuDriverVersion = "460.73.01"
        Int nThreads = 32
        Int gbRAM = 120
        Int diskGB = 0
        Int runtimeMinutes = 600
        String hpcQueue = "gpu"
        Int maxPreemptAttempts = 3
    }

    String ref = basename(inputRefTarball, ".tar")
    String outbase = basename(tumorBAM, ".bam") + "." + basename(normalBAM, ".bam") + ".mutectcaller"

    Int auto_diskGB = if diskGB == 0 then ceil(size(tumorBAM, "GB")) + ceil(size(tumorBAM, "GB")) + ceil(size(inputRefTarball, "GB")) + 85 else diskGB

    command {
        time tar xf ~{inputRefTarball} && \
        time ~{pbPATH} mutect2 \
        --ref ~{ref} \
        --tumor-name ~{tumorName} \
        --normal-name ~{normalName} \
        --in-tumor-bam ~{normalBAM} \
        --in-normal-bam ~{normalBAM} \
        ~{"--pon " + ponVCF} \
        --license-file ~{pbLicenseBin} \
        --out-vcf ~{outbase}.vcf
    }
    output {
        File outputVCF = "~{outbase}.vcf"
    }
    runtime {
        docker : "~{pbDocker}"
        disks : "local-disk ~{auto_diskGB} SSD"
        cpu : nThreads
        memory : "~{gbRAM} GB"
        hpcMemory : gbRAM
        hpcQueue : "~{hpcQueue}"
        hpcRuntimeMinutes : runtimeMinutes
        gpuType : "~{gpuModel}"
        gpuCount : nGPU
        nvidiaDriverVersion : "~{gpuDriverVersion}"
        zones : ["us-central1-a", "us-central1-b", "us-central1-c"]
        preemptible : maxPreemptAttempts
    }
}

task mutect2_postpon {
    input {
        File inputVCF
        File ponFile
        File ponVCF
        File ponTBI
        String pbPATH
        File pbLicenseBin
        String? pbDocker
        Int nGPU = 4
        String gpuModel = "nvidia-tesla-v100"
        String gpuDriverVersion = "460.73.01"
        Int nThreads = 32
        Int gbRAM = 120
        Int diskGB = 0
        Int runtimeMinutes = 600
        String hpcQueue = "gpu"
        Int maxPreemptAttempts = 3
    }
    Int auto_diskGB = if diskGB == 0 then ceil(size(inputVCF, "GB") * 2.5) + ceil(size(ponFile, "GB")) + ceil(size(ponVCF, "GB"))  + 65 else diskGB

    String outbase = basename(basename(inputVCF, ".gz"), ".vcf")

    command {
        time ${pbPATH} postpon \
        --in-vcf ~{inputVCF} \
        --in-pon-file ~{ponVCF} \
        --out-vcf ~{outbase}.postpon.vcf
    }
    output {
        File outputVCF = "~{outbase}.postpon.vcf"
    }
    runtime {
        docker : "~{pbDocker}"
        disks : "local-disk ~{auto_diskGB} SSD"
        cpu : nThreads
        memory : "~{gbRAM} GB"
        hpcMemory : gbRAM
        hpcQueue : "~{hpcQueue}"
        hpcRuntimeMinutes : runtimeMinutes
        gpuType : "~{gpuModel}"
        gpuCount : nGPU
        nvidiaDriverVersion : "~{gpuDriverVersion}"
        zones : ["us-central1-a", "us-central1-b", "us-central1-c"]
        preemptible : maxPreemptAttempts
    }
}

task compressAndIndexVCF {
    input {
        File inputVCF
        String? bgzipDocker
        Int nThreads = 32
        Int gbRAM = 120
        Int diskGB = 0
        Int runtimeMinutes = 600
        String hpcQueue = "norm"
        Int maxPreemptAttempts = 3
    }
    Int auto_diskGB = if diskGB == 0 then ceil(size(inputVCF, "GB") * 2.0) + 40 else diskGB

    command {
        bgzip -@ ~{nThreads} ~{inputVCF} && \
        tabix ~{inputVCF}.gz
    }
    output {
        File outputVCF = "~{inputVCF}.gz"
        File outputTBI = "~{inputVCF}.gz.tbi"
    }
    runtime {
        docker : "~{bgzipDocker}"
        disks : "local-disk ~{auto_diskGB} SSD"
        cpu : nThreads
        memory : "~{gbRAM} GB"
        hpcMemory : gbRAM
        hpcQueue : "~{hpcQueue}"
        hpcRuntimeMinutes : runtimeMinutes
        zones : ["us-central1-a", "us-central1-b", "us-central1-c"]
        preemptible : maxPreemptAttempts
    }
}

workflow ClaraParabricks_Somatic {
    input {
        File tumorBAM
        File tumorBAI
        String tumorName
        File normalBAM
        File normalBAI
        String normalName
        File inputRefTarball
        String pbPATH
        File pbLicenseBin
        File? ponVCF
        File? ponTBI
        String? pbDocker
        Int nGPU = 4
        String gpuModel = "nvidia-tesla-v100"
        String gpuDriverVersion = "460.73.01"
        Int nThreads = 32
        Int gbRAM = 120
        Int diskGB = 0
        Int runtimeMinutes = 600
        String hpcQueue = "gpu"
        Int maxPreemptAttempts = 3
    }

    Boolean doPON = defined(ponVCF)

    if (doPON){
        call mutect2_prepon{
            input:
                ponVCF=select_first([ponVCF]),
                ponTBI=select_first([ponTBI]),
                pbPATH=pbPATH,
                pbLicenseBin=pbLicenseBin,
                pbDocker=pbDocker,
                nGPU=nGPU,
                gpuModel=gpuModel,
                gpuDriverVersion=gpuDriverVersion,
                nThreads=nThreads,
                gbRAM=gbRAM,
                diskGB=diskGB,
                runtimeMinutes=runtimeMinutes,
                hpcQueue=hpcQueue,
                maxPreemptAttempts=maxPreemptAttempts
        }
    }

    File ponFile = select_first([mutect2_prepon.outputPON])

    call mutect2_call as pb_mutect2 {
        input:
            tumorBAM=tumorBAM,
            tumorBAI=tumorBAI,
            tumorName=tumorName,
            normalBAM=normalBAM,
            normalBAI=normalBAI,
            normalName=normalName,
            inputRefTarball=inputRefTarball,
            ponFile=ponFile,
            ponVCF=ponVCF,
            ponTBI=ponTBI,
            pbPATH=pbPATH,
            pbLicenseBin=pbLicenseBin,
            pbDocker=pbDocker,
            nGPU=nGPU,
            gpuModel=gpuModel,
            gpuDriverVersion=gpuDriverVersion,
            nThreads=nThreads,
            gbRAM=gbRAM,
            diskGB=diskGB,
            runtimeMinutes=runtimeMinutes,
            hpcQueue=hpcQueue,
            maxPreemptAttempts=maxPreemptAttempts
    }

    if (doPON){
        call mutect2_postpon {
            input:
                inputVCF=pb_mutect2.outputVCF,
                ponFile=select_first([mutect2_prepon.outputPON]),
                ponVCF=select_first([ponVCF]),
                ponTBI=select_first([ponTBI]),
                pbPATH=pbPATH,
                pbLicenseBin=pbLicenseBin,
                pbDocker=pbDocker,
                nGPU=nGPU,
                gpuModel=gpuModel,
                gpuDriverVersion=gpuDriverVersion,
        }
    }

    File to_compress_VCF = if doPON then select_first([mutect2_postpon.outputVCF]) else pb_mutect2.outputVCF

    call compressAndIndexVCF {
        input:
            inputVCF=to_compress_VCF
    }

    output {
        File outputVCF = compressAndIndexVCF.outputVCF
        File outputTBI = compressAndIndexVCF.outputTBI
    }
}