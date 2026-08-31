#ifndef HEXCORE_ARRAYS_H
#define HEXCORE_ARRAYS_H
#include <Python.h>
PyObject *hc_zoom(PyObject *src);
PyObject *hc_mirror(PyObject *src);
PyObject *hc_total(PyObject *src);
PyObject *hc_clamp_temp(PyObject *base);
int hc_commit_clamp(PyObject *tmp);
#endif
