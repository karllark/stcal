import logging
import numpy as np
from . import util
from gwcs.wcstools import grid_from_bounding_box

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)


def calc_pixmap(in_wcs, out_wcs, shape=None):
    """Return a pixel grid map from input frame to output frame

    Parameters
    ----------
    in_wcs: `~astropy.wcs.WCS`
        Input WCS objects or transforms.
    out_wcs: `~astropy.wcs.WCS` or `~gwcs.wcs.WCS`
        output WCS objects or transforms.
    shape : tuple, optional
        Shape of grid in pixels. The default is None.

    Returns
    -------
    pixmap
        reprojected pixel grid map
    """
    if shape:
        bb = util.wcs_bbox_from_shape(shape)
        log.debug("Bounding box from data shape: {}".format(bb))
    else:
        bb = util.wcs_bbox_from_shape(in_wcs.pixel_shape)
        log.debug("Bounding box from WCS: {}".format(bb))

    grid = grid_from_bounding_box(bb)
    pixmap = np.dstack(util.reproject(in_wcs, out_wcs)(grid[0], grid[1]))
    return pixmap
