#
# Copyright (c) 2019, NVIDIA CORPORATION.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# cython: profile=False
# distutils: language = c++
# cython: embedsignature = True
# cython: language_level = 3

from cuml.neighbors.knn cimport *

import numpy as np
import pandas as pd
import cudf
import ctypes

from cuml import numba_utils


from librmm_cffi import librmm as rmm
from cython.operator cimport dereference as deref
from numba import cuda

from libc.stdint cimport uintptr_t
from libc.stdlib cimport calloc, malloc, free

cdef extern from "umap/umapparams.h" namespace "ML":

    cdef cppclass UMAPParams:
        int n_neighbors,
        int n_components,
        int n_epochs,
        float learning_rate,
        float min_dist,
        float spread,
        int init,
        float set_op_mix_ratio,
        float local_connectivity,
        float repulsion_strength,
        int negative_sample_rate,
        float transform_queue_size


cdef extern from "umap/umap.h" namespace "ML":
    cdef cppclass UMAP:

        UMAP(UMAPParams *p) except +

        void fit(float *X,
                 int n,
                 int d,
                 kNN *knn,
                 float *embeddings)

        void transform(float *X,
                       int n,
                       int d,
                       float *embedding,
                       int embedding_n,
                       kNN *knn,
                       float *out)

cdef class UMAP1:

    cpdef UMAPParams *umap_params
    cpdef UMAP *umap
    cpdef kNN *knn
    cdef uintptr_t embeddings
    cdef uintptr_t raw_data

    def __cinit__(self):
        """
        Construct the kNN object for training and querying.

        Parameters
        ----------
        should_downcast: Bool
            Currently only single precision is supported in the underlying undex. Setting this to
            true will allow single-precision input arrays to be automatically downcasted to single
            precision. Default = False.
        """

    def __dealloc__(self):
        print("DEALLOC!")
        del self.umap_params
        del self.umap
        del self.knn


    def fit(self, X,
            n_neighbors = 2,
            n_components = 2,
            n_epochs = 500,
            learning_rate = 1.0,
            min_dist = 0.1,
            spread = 1.0,
            set_op_mix_ratio = 1.0,
            local_connectivity = 1.0,
            repulsion_strength = 1.0,
            negative_sample_rate = 5,
            transform_queue_size = 4.0,
            init = "spectral"):

        if self.umap_params != NULL:
            del self.umap_params

        if self.umap != NULL:
            del self.umap

        if self.knn != NULL:
            del self.knn

        """
        Fit a UMAP model
        """
        assert len(X.shape) == 2, 'data should be two dimensional'

        X_m = numba_utils.row_matrix(X)
        self.raw_data = X_m.device_ctypes_pointer.value

        arr_embed = cuda.to_device(np.zeros((X_m.shape[0], n_components), order = "C", dtype=np.float32))
        self.embeddings = arr_embed.device_ctypes_pointer.value

        self.knn = new kNN(X_m.shape[1])

        print("kNN D=" + str(X_m.shape[1]))

        self.umap_params = new UMAPParams()
        self.umap_params.n_neighbors = <int>n_neighbors
        self.umap_params.n_components = <int>n_components
        self.umap_params.n_epochs = <int>n_epochs

        if(init == "spectral"):
            self.umap_params.init = <int>1
        elif(init == "random"):
            self.umap_params.init = <int>0
        else:
            raise Exception("Initialization strategy not support: [init=%d]" % init)

        self.umap_params.learning_rate = <float>learning_rate
        self.umap_params.min_dist = <float>min_dist
        self.umap_params.spread = <float>spread
        self.umap_params.set_op_mix_ratio = <float>set_op_mix_ratio
        self.umap_params.local_connectivity = <float>local_connectivity
        self.umap_params.repulsion_strength = <float>repulsion_strength
        self.umap_params.negative_sample_rate = <int>negative_sample_rate
        self.umap_params.transform_queue_size = <int>transform_queue_size

        self.umap = new UMAP(self.umap_params)

        self.umap.fit(
            <float*> self.raw_data,
            <int> X_m.shape[0],
            <int> X_m.shape[1],
            <kNN*> self.knn,
            <float*>self.embeddings
        )

        del X_m

        return arr_embed
