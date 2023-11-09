"""
Define the C class for the Cassertano22 algorithm for fitting ramps with jump detection

Objects
-------
Pixel : class
    Class to handle ramp fit with jump detection for a single pixel
    Provides fits method which fits all the ramps for a single pixel

Functions
---------
    make_pixel : function
        Fast constructor for a Pixel class from input data.
            - cpdef gives a python wrapper, but the python version of this method
              is considered private, only to be used for testing
"""
import numpy as np
cimport numpy as cnp

from libc.math cimport NAN
from cython cimport boundscheck, wraparound, cdivision

from stcal.ramp_fitting.ols_cas22._core cimport Diff, n_diff
from stcal.ramp_fitting.ols_cas22._fixed cimport FixedValues
from stcal.ramp_fitting.ols_cas22._pixel cimport Pixel




cnp.import_array()


cdef class Pixel:
    """
    Class to contain the data to fit ramps for a single pixel.
        This data is drawn from for all ramps for a single pixel.
        This class pre-computes jump detection values shared by all ramps
        for a given pixel.

    Parameters
    ----------
    fixed : FixedValues
        The object containing all the values and metadata which is fixed for a
        given read pattern>
    read_noise : float
        The read noise for the given pixel
    resultants : float [:]
        Resultants input for the given pixel

    local_slopes : float [:, :]
        These are the local slopes between the resultants for the pixel.
            single difference local slope:
                local_slopes[Diff.single, :] = (resultants[i+1] - resultants[i])
                                                / (t_bar[i+1] - t_bar[i])
            double difference local slope:
                local_slopes[Diff.double, :] = (resultants[i+2] - resultants[i])
                                                / (t_bar[i+2] - t_bar[i])
    var_read_noise : float [:, :]
        The read noise variance term of the jump statistics
            single difference read noise variance:
                var_read_noise[Diff.single, :] = read_noise * ((1/n_reads[i+1]) + (1/n_reads[i]))
            double difference read_noise variance:
                var_read_noise[Diff.doule, :] = read_noise * ((1/n_reads[i+2]) + (1/n_reads[i]))

    Notes
    -----
    - local_slopes and var_read_noise are only computed if use_jump is True. 
      These values represent reused computations for jump detection which are
      used by every ramp for the given pixel for jump detection. They are
      computed once and stored for reuse by all ramp computations for the pixel.
    - The computations are done using vectorized operations for some performance
      increases. However, this is marginal compaired with the performance increase
      from pre-computing the values and reusing them.

    Methods
    -------
    fit_ramp (ramp_index) : method
        Compute the ramp fit for a single ramp defined by an inputed RampIndex
    fit_ramps (ramp_stack) : method
        Compute all the ramps for a single pixel using the Casertano+22 algorithm
        with jump detection.
    """


    def _to_dict(Pixel self):
        """
        This is a private method to convert the Pixel object to a dictionary, so
            that attributes can be directly accessed in python. Note that this is
            needed because class attributes cannot be accessed on cython classes
            directly in python. Instead they need to be accessed or set using a
            python compatible method. This method is a pure puthon method bound
            to to the cython class and should not be used by any cython code, and
            only exists for testing purposes.
        """

        cdef cnp.ndarray[float, ndim=1] resultants_ = np.array(self.resultants, dtype=np.float32)

        cdef cnp.ndarray[float, ndim=2] local_slopes
        cdef cnp.ndarray[float, ndim=2] var_read_noise

        if self.fixed.use_jump:
            local_slopes = np.array(self.local_slopes, dtype=np.float32)
            var_read_noise = np.array(self.var_read_noise, dtype=np.float32)
        else:
            try:
                self.local_slopes
            except AttributeError:
                local_slopes = np.array([[np.nan],[np.nan]], dtype=np.float32)
            else:
                raise AttributeError("local_slopes should not exist")

            try:
                self.var_read_noise
            except AttributeError:
                var_read_noise = np.array([[np.nan],[np.nan]], dtype=np.float32)
            else:
                raise AttributeError("var_read_noise should not exist")

        return dict(fixed=self.fixed._to_dict(),
                    resultants=resultants_,
                    read_noise=self.read_noise,
                    local_slopes=local_slopes,
                    var_read_noise=var_read_noise)

cdef enum Offsets:
    single_slope
    double_slope
    single_var
    double_var
    n_offsets


@boundscheck(False)
@wraparound(False)
@cdivision(True)
cdef inline float[:, :] local_slope_vals(float[:] resultants,
                                         float[:, :] t_bar_diffs,
                                         float[:, :] read_recip_coeffs,
                                         float read_noise,
                                         int end):
    """
    Compute the local slopes between resultants for the pixel

    Returns
    -------
    [
        <(resultants[i+1] - resultants[i])> / <(t_bar[i+1] - t_bar[i])>,
        <(resultants[i+2] - resultants[i])> / <(t_bar[i+2] - t_bar[i])>,
    ]
    """
    cdef int single = Diff.single
    cdef int double = Diff.double

    cdef int single_slope = Offsets.single_slope
    cdef int double_slope = Offsets.double_slope
    cdef int single_var = Offsets.single_var
    cdef int double_var = Offsets.double_var

    cdef float[:, :] pre_compute = np.empty((n_offsets, end - 1), dtype=np.float32)
    cdef float read_noise_sqr = read_noise ** 2

    cdef int i
    for i in range(end - 1):
        pre_compute[single_slope, i] = (resultants[i + 1] - resultants[i]) / t_bar_diffs[single, i]

        if i < end - 2:
            pre_compute[double_slope, i] = (resultants[i + 2] - resultants[i]) / t_bar_diffs[double, i]
        else:
            pre_compute[double_slope, i] = NAN  # last double difference is undefined

        pre_compute[single_var, i] = read_noise_sqr * read_recip_coeffs[single, i]
        pre_compute[double_var, i] = read_noise_sqr * read_recip_coeffs[double, i]

    return pre_compute


@boundscheck(False)
@wraparound(False)
cpdef inline Pixel make_pixel(FixedValues fixed, float read_noise, float [:] resultants):
    """
    Fast constructor for the Pixel C class.
        This creates a Pixel object for a single pixel from the input data.

    This is signifantly faster than using the `__init__` or `__cinit__`
        this is because this does not have to pass through the Python as part
        of the construction.

    Parameters
    ----------
    fixed : FixedValues
        Fixed values for all pixels
    read_noise : float
        read noise for the single pixel
    resultants : float [:]
        array of resultants for the single pixel
            - memoryview of a numpy array to avoid passing through Python

    Return
    ------
    Pixel C-class object (with pre-computed values if use_jump is True)
    """
    cdef Pixel pixel = Pixel()

    # Fill in input information for pixel
    pixel.fixed = fixed
    pixel.read_noise = read_noise
    pixel.resultants = resultants

    # Pre-compute values for jump detection shared by all pixels for this pixel
    cdef float[:, :] pre_compute
    cdef int n_resultants = len(resultants)
    if fixed.use_jump:
        pre_compute = local_slope_vals(resultants, fixed.t_bar_diffs, fixed.read_recip_coeffs, read_noise, n_resultants)
        pixel.local_slopes = pre_compute[:n_diff, :]
        pixel.var_read_noise = pre_compute[n_diff:n_offsets, :]

    return pixel
