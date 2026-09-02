; ------------------------------------------------------------------
; VINE TERRACE -- RGC channel mechanisms (NEURON-style specification)
; The pipeline must port these three mechanisms into Jaxley Channel
; classes and attach them to a loaded SWC morphology.
; Units: membrane current density mA/cm^2, voltage mV, time ms.
; ------------------------------------------------------------------

TITLE compact RGC fast-spiking conductances
INDEPENDENT {t FROM 0 TO 1 WITH 1 (ms)}

NEURON {
    SUFFIX jnaf
    USEION na READ ena WRITE ina : reversal ena (mV)
    RANGE gmax
}
PARAMETER { gmax = 0.120 (S/cm2) }
STATE { m h }
INITIAL { m=0.05 h=0.6 }
BREAKPOINT {
    ina = gmax * m*m*m * h * (v - ena)
}
DERIVATIVE states {
    : rate functions, v in mV
    am(v) = if abs(v+40)<1e-8 then 1 else (v+40)/(1-exp(-(v+40)/10))
    bm(v) = 4*exp(-(v+65)/18)
    ah(v) = 0.07*exp(-(v+65)/20)
    bh(v) = 1/(1+exp(-(v+35)/10))
    m' = am*(1-m) - bm*m
    h' = ah*(1-h) - bh*h
}

TITLE delayed-rectifier-like potassium
NEURON {
    SUFFIX jkd
    USEION k READ ek WRITE ik : reversal ek (mV)
    RANGE gmax
}
PARAMETER { gmax = 0.036 (S/cm2) }
STATE { n }
INITIAL { n=0.3 }
BREAKPOINT {
    ik = gmax * n*n*n*n * (v - ek)
}
DERIVATIVE states {
    an(v) = if abs(v+55)<1e-8 then 0.1 else 0.01*(v+55)/(1-exp(-(v+55)/10))
    bn(v) = 0.125*exp(-(v+65)/80)
    n' = an*(1-n) - bn*n
}

TITLE passive leak
NEURON {
    SUFFIX jleak
    RANGE gleak, eleak
}
PARAMETER { gleak = 0.0003 (S/cm2) eleak = -54.3 (mV) }
BREAKPOINT { ileak = gleak * (v - eleak) }
