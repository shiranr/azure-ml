# Copyright (c) Microsoft Corporation. All rights reserved.

# Licensed under the MIT License.

 
FROM mcr.microsoft.com/azureml/o16n-base/python-assets:20230222.v4 AS inferencing-assets

 
# Tag: cuda:11.8.0-cudnn8-devel-ubuntu22.04

# Env: CUDA_VERSION=11.8.0

# Env: NCCL_VERSION=2.12.7-1

# Env: NV_CUDNN_VERSION=8.4.0.27

 

# DisableDockerDetector "Preferred to use nvidia registry over MCR mirror"

FROM nvcr.io/nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04


USER root:root 

ARG IMAGE_NAME=None

ARG BUILD_NUMBER=None

ENV com.nvidia.cuda.version $CUDA_VERSION
ENV com.nvidia.volumes.needed nvidia_driver
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64
ENV NCCL_DEBUG=INFO
ENV HOROVOD_GPU_ALLREDUCE=NCCL 

# Install Common Dependencies

RUN apt-get update &&\
    apt-get install -y --no-install-recommends &&\
    # Others
    apt-get install -y \
    libksba8 \
    cuda-compat-11-8 \
    openssl \
    libxrender-dev \
    libssl3 \
    git && \
    # nccl-rdma-sharp-plugins dependencies
    apt-get install -y \
    libnuma-dev \
    libgnutls30 \
    tar \
    libsystemd0 \
    libudev1 \
    libibverbs-dev &&\
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Inference

# Copy logging utilities, nginx and rsyslog configuration files, IOT server binary, etc.

COPY --from=inferencing-assets /artifacts /var/

RUN sed -i '/liblttng-ust0/d' /var/requirements/system_requirements.txt

RUN sed -i '/liblttng-ust0/d' /var/requirements/system_requirements_ubuntu_19.txt

RUN /var/requirements/install_system_requirements.sh && \
    cp /var/configuration/rsyslog.conf /etc/rsyslog.conf && \
    cp /var/configuration/nginx.conf /etc/nginx/sites-available/app && \
    ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app && \
    rm -f /etc/nginx/sites-enabled/default

ENV SVDIR=/var/runit

ENV WORKER_TIMEOUT=300

EXPOSE 5001 8883 8888

# Stores image version information and log it while running inferencing server for better Debuggability

RUN if [ "$BUILD_NUMBER" != "None" ] && [ "$IMAGE_NAME" != "None" ]; then echo "${IMAGE_NAME}, Materializaton Build:${BUILD_NUMBER}" > /IMAGE_INFORMATION ; fi

# Conda Environment

ENV MINICONDA_VERSION py38_4.12.0

ENV PATH /opt/miniconda/bin:$PATH

ENV CONDA_PACKAGE 22.11.1

RUN wget -qO /tmp/miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-${MINICONDA_VERSION}-Linux-x86_64.sh && \
    bash /tmp/miniconda.sh -bf -p /opt/miniconda && \
    conda clean -ay && \
    conda install conda=${CONDA_PACKAGE} -y && \
    conda install wheel=0.38.1 setuptools=65.5.1 cryptography=39.0.1 -c conda-forge -y && \
    rm -rf /opt/miniconda/pkgs && \
    rm /tmp/miniconda.sh && \
    find / -type d -name __pycache__ | xargs rm -rf
 

#Cmake Installation
RUN apt-get update && \
    apt-get install -y cmake

 
# Open-MPI installation

ENV OPENMPI_VERSION 3.1.2

RUN mkdir /tmp/openmpi && \
    cd /tmp/openmpi && \
    wget https://download.open-mpi.org/release/open-mpi/v3.1/openmpi-${OPENMPI_VERSION}.tar.gz && \
    tar zxf openmpi-${OPENMPI_VERSION}.tar.gz && \
    cd openmpi-${OPENMPI_VERSION} && \
    ./configure --enable-orterun-prefix-by-default && \
    make -j $(nproc) all && \
    make install && \
    ldconfig && \
    rm -rf /tmp/openmpi
 

# Msodbcsql17 installation

RUN apt-get update && \
    apt-get install -y curl && \
    curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
    curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y msodbcsql17 unixodbc-dev
 

#Install latest version of nccl-rdma-sharp-plugins

RUN cd /tmp && \
    mkdir -p /usr/local/nccl-rdma-sharp-plugins && \
    apt install -y dh-make zlib1g-dev nvidia-driver-470 && \
    git clone -b v2.1.0 https://github.com/Mellanox/nccl-rdma-sharp-plugins.git && \
    cd nccl-rdma-sharp-plugins && \
    ./autogen.sh && \
    ./configure --prefix=/usr/local/nccl-rdma-sharp-plugins --with-cuda=/usr/local/cuda --without-ucx && \
    make && \
    make install

 

RUN apt remove -y cuda-compat-11-8
# set env var to find nccl rdma plugins inside this container
ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/nccl-rdma-sharp-plugins/lib:/usr/lib/x86_64-linux-gnu
RUN sudo ln -s /usr/lib/x86_64-linux-gnu/libcuda.so.470.182.03 /usr/lib/wsl/lib/libcuda.so.1 /usr/local/cuda/lib64/libcuda.so

