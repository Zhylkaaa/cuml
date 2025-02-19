# Copyright (c) 2018-2022, NVIDIA CORPORATION.
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

# distutils: language = c++

import ctypes
import numpy as np

from numba import cuda

from libcpp cimport bool
from libc.stdint cimport uintptr_t
from libc.stdlib cimport calloc, malloc, free

from cuml.common import CumlArray
from cuml.common.array_descriptor import CumlArrayDescriptor
from cuml.common.base import Base
from cuml.common.doc_utils import generate_docstring
from raft.common.handle cimport handle_t
from cuml.common.input_utils import input_to_cuml_array
from cuml.common.mixins import FMajorInputTagMixin


cdef extern from "cuml/solvers/solver.hpp" namespace "ML::Solver":

    cdef void cdFit(handle_t& handle,
                    float *input,
                    int n_rows,
                    int n_cols,
                    float *labels,
                    float *coef,
                    float *intercept,
                    bool fit_intercept,
                    bool normalize,
                    int epochs,
                    int loss,
                    float alpha,
                    float l1_ratio,
                    bool shuffle,
                    float tol,
                    float *sample_weight) except +

    cdef void cdFit(handle_t& handle,
                    double *input,
                    int n_rows,
                    int n_cols,
                    double *labels,
                    double *coef,
                    double *intercept,
                    bool fit_intercept,
                    bool normalize,
                    int epochs,
                    int loss,
                    double alpha,
                    double l1_ratio,
                    bool shuffle,
                    double tol,
                    double *sample_weight) except +

    cdef void cdPredict(handle_t& handle,
                        const float *input,
                        int n_rows,
                        int n_cols,
                        const float *coef,
                        float intercept,
                        float *preds,
                        int loss) except +

    cdef void cdPredict(handle_t& handle,
                        const double *input,
                        int n_rows,
                        int n_cols,
                        const double *coef,
                        double intercept,
                        double *preds,
                        int loss) except +


class CD(Base,
         FMajorInputTagMixin):
    """
    Coordinate Descent (CD) is a very common optimization algorithm that
    minimizes along coordinate directions to find the minimum of a function.

    cuML's CD algorithm accepts a numpy matrix or a cuDF DataFrame as the
    input dataset.algorithm The CD algorithm currently works with linear
    regression and ridge, lasso, and elastic-net penalties.

    Examples
    ---------
    .. code-block:: python

        >>> import cupy as cp
        >>> import cudf
        >>> from cuml.solvers import CD as cumlCD

        >>> cd = cumlCD(alpha=0.0)

        >>> X = cudf.DataFrame()
        >>> X['col1'] = cp.array([1,1,2,2], dtype=cp.float32)
        >>> X['col2'] = cp.array([1,2,2,3], dtype=cp.float32)

        >>> y = cudf.Series(cp.array([6.0, 8.0, 9.0, 11.0], dtype=cp.float32))

        >>> cd.fit(X,y)
        CD()
        >>> print(cd.coef_) # doctest: +SKIP
        0 1.001...
        1 1.998...
        dtype: float32
        >>> print(cd.intercept_) # doctest: +SKIP
        3.00...
        >>> X_new = cudf.DataFrame()
        >>> X_new['col1'] = cp.array([3,2], dtype=cp.float32)
        >>> X_new['col2'] = cp.array([5,5], dtype=cp.float32)

        >>> preds = cd.predict(X_new)
        >>> print(preds) # doctest: +SKIP
        0 15.997...
        1 14.995...
        dtype: float32

    Parameters
    -----------
    loss : 'squared_loss'
        Only 'squared_loss' is supported right now.
        'squared_loss' uses linear regression in its predict step.
    alpha: float (default = 0.0001)
        The constant value which decides the degree of regularization.
        'alpha = 0' is equivalent to an ordinary least square, solved by the
        LinearRegression object.
    l1_ratio: float (default = 0.15)
        The ElasticNet mixing parameter, with 0 <= l1_ratio <= 1. For
        l1_ratio = 0 the penalty is an L2 penalty.
        For l1_ratio = 1 it is an L1 penalty. For 0 < l1_ratio < 1,
        the penalty is a combination of L1 and L2.
    fit_intercept : boolean (default = True)
       If True, the model tries to correct for the global mean of y.
       If False, the model expects that you have centered the data.
    normalize : boolean (default = False)
        Whether to normalize the data or not.
    max_iter : int (default = 1000)
        The number of times the model should iterate through the entire
        dataset during training
    tol : float (default = 1e-3)
       The tolerance for the optimization: if the updates are smaller than tol,
       solver stops.
    shuffle : boolean (default = True)
       If set to 'True', a random coefficient is updated every iteration rather
       than looping over features sequentially by default.
       This (setting to 'True') often leads to significantly faster convergence
       especially when tol is higher than 1e-4.
    handle : cuml.Handle
        Specifies the cuml.handle that holds internal CUDA state for
        computations in this model. Most importantly, this specifies the CUDA
        stream that will be used for the model's computations, so users can
        run different models concurrently in different streams by creating
        handles in several streams.
        If it is None, a new one is created.
    verbose : int or boolean, default=False
        Sets logging level. It must be one of `cuml.common.logger.level_*`.
        See :ref:`verbosity-levels` for more info.
    output_type : {'input', 'cudf', 'cupy', 'numpy', 'numba'}, default=None
        Variable to control output type of the results and attributes of
        the estimator. If None, it'll inherit the output type set at the
        module level, `cuml.global_settings.output_type`.
        See :ref:`output-data-type-configuration` for more info.

    """

    coef_ = CumlArrayDescriptor()

    def __init__(self, *, loss='squared_loss', alpha=0.0001, l1_ratio=0.15,
                 fit_intercept=True, normalize=False, max_iter=1000, tol=1e-3,
                 shuffle=True, handle=None, output_type=None, verbose=False):

        if loss not in ['squared_loss']:
            msg = "loss {!r} is not supported"
            raise NotImplementedError(msg.format(loss))

        super().__init__(handle=handle,
                         verbose=verbose,
                         output_type=output_type)

        self.loss = loss
        self.alpha = alpha
        self.l1_ratio = l1_ratio
        self.fit_intercept = fit_intercept
        self.normalize = normalize
        self.max_iter = max_iter
        self.tol = tol
        self.shuffle = shuffle
        self.intercept_value = 0.0
        self.coef_ = None
        self.intercept_ = None

    def _check_alpha(self, alpha):
        for el in alpha:
            if el <= 0.0:
                msg = "alpha values have to be positive"
                raise TypeError(msg.format(alpha))

    def _get_loss_int(self):
        return {
            'squared_loss': 0,
        }[self.loss]

    @generate_docstring()
    def fit(self, X, y, convert_dtype=False, sample_weight=None) -> "CD":
        """
        Fit the model with X and y.

        """
        cdef uintptr_t sample_weight_ptr
        X_m, n_rows, self.n_cols, self.dtype = \
            input_to_cuml_array(X, check_dtype=[np.float32, np.float64])

        y_m, *_ = \
            input_to_cuml_array(y, check_dtype=self.dtype,
                                convert_to_dtype=(self.dtype if convert_dtype
                                                  else None),
                                check_rows=n_rows, check_cols=1)

        if sample_weight is not None:
            sample_weight_m, _, _, _ = \
                input_to_cuml_array(sample_weight, check_dtype=self.dtype,
                                    convert_to_dtype=(
                                        self.dtype if convert_dtype else None),
                                    check_rows=n_rows, check_cols=1)
            sample_weight_ptr = sample_weight_m.ptr
        else:
            sample_weight_ptr = 0

        cdef uintptr_t X_ptr = X_m.ptr
        cdef uintptr_t y_ptr = y_m.ptr

        self.n_alpha = 1

        self.coef_ = CumlArray.zeros(self.n_cols, dtype=self.dtype)
        cdef uintptr_t coef_ptr = self.coef_.ptr

        cdef float c_intercept1
        cdef double c_intercept2
        cdef handle_t* handle_ = <handle_t*><size_t>self.handle.getHandle()

        if self.dtype == np.float32:
            cdFit(handle_[0],
                  <float*>X_ptr,
                  <int>n_rows,
                  <int>self.n_cols,
                  <float*>y_ptr,
                  <float*>coef_ptr,
                  <float*>&c_intercept1,
                  <bool>self.fit_intercept,
                  <bool>self.normalize,
                  <int>self.max_iter,
                  <int>self._get_loss_int(),
                  <float>self.alpha,
                  <float>self.l1_ratio,
                  <bool>self.shuffle,
                  <float>self.tol,
                  <float*>sample_weight_ptr)

            self.intercept_ = c_intercept1
        else:
            cdFit(handle_[0],
                  <double*>X_ptr,
                  <int>n_rows,
                  <int>self.n_cols,
                  <double*>y_ptr,
                  <double*>coef_ptr,
                  <double*>&c_intercept2,
                  <bool>self.fit_intercept,
                  <bool>self.normalize,
                  <int>self.max_iter,
                  <int>self._get_loss_int(),
                  <double>self.alpha,
                  <double>self.l1_ratio,
                  <bool>self.shuffle,
                  <double>self.tol,
                  <double*>sample_weight_ptr)

            self.intercept_ = c_intercept2

        self.handle.sync()
        del X_m
        del y_m
        if sample_weight is not None:
            del sample_weight_m

        return self

    @generate_docstring(return_values={'name': 'preds',
                                       'type': 'dense',
                                       'description': 'Predicted values',
                                       'shape': '(n_samples, 1)'})
    def predict(self, X, convert_dtype=False) -> CumlArray:
        """
        Predicts the y for X.

        """
        X_m, n_rows, n_cols, dtype = \
            input_to_cuml_array(X, check_dtype=self.dtype,
                                convert_to_dtype=(self.dtype if convert_dtype
                                                  else None),
                                check_cols=self.n_cols)

        cdef uintptr_t X_ptr = X_m.ptr
        cdef uintptr_t coef_ptr = self.coef_.ptr

        preds = CumlArray.zeros(n_rows, dtype=self.dtype,
                                index=X_m.index)
        cdef uintptr_t preds_ptr = preds.ptr

        cdef handle_t* handle_ = <handle_t*><size_t>self.handle.getHandle()

        if self.dtype == np.float32:
            cdPredict(handle_[0],
                      <float*>X_ptr,
                      <int>n_rows,
                      <int>n_cols,
                      <float*>coef_ptr,
                      <float>self.intercept_,
                      <float*>preds_ptr,
                      <int>self._get_loss_int())
        else:
            cdPredict(handle_[0],
                      <double*>X_ptr,
                      <int>n_rows,
                      <int>n_cols,
                      <double*>coef_ptr,
                      <double>self.intercept_,
                      <double*>preds_ptr,
                      <int>self._get_loss_int())

        self.handle.sync()

        del(X_m)

        return preds

    def get_param_names(self):
        return super().get_param_names() + [
            "loss",
            "alpha",
            "l1_ratio",
            "fit_intercept",
            "normalize",
            "max_iter",
            "tol",
            "shuffle",
        ]
