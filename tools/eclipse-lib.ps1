# Reference implementation of the eclipse algorithm in source/MoonPhase.mc.
# Meeus, Astronomical Algorithms 2nd ed., chapters 49 and 54.
#
# Dot-source this; it defines functions only. Kept separate from the validator
# so the same code can be exercised on a single date without the full sweep.

$script:JD_2000 = 2451544.5   # JD at 2000-01-01 00:00 UTC
$script:WINDOW  = 0.25        # +/- 6 h effect window

function D2R([double]$d) { return $d * [math]::PI / 180.0 }
function SinD([double]$d) { return [math]::Sin((D2R $d)) }
function CosD([double]$d) { return [math]::Cos((D2R $d)) }

# Meeus ch.54. $k integer for solar, integer+0.5 for lunar.
# Returns $null when no eclipse, else a hashtable with Jde/Kind/Type/Mag/Gamma.
function EclipseForK([double]$k) {
    $T  = $k / 1236.85
    $T2 = $T * $T; $T3 = $T2 * $T; $T4 = $T3 * $T

    $F = 160.7108 + 390.67050284 * $k - 0.0016118 * $T2 - 0.00000227 * $T3 + 0.000000011 * $T4
    # No eclipse is possible unless the Moon is near a node.
    if ([math]::Abs((SinD $F)) -gt 0.36) { return $null }

    $M  = 2.5534 + 29.10535670 * $k - 0.0000014 * $T2 - 0.00000011 * $T3
    $Mp = 201.5643 + 385.81693528 * $k + 0.0107582 * $T2 + 0.00001238 * $T3 - 0.000000058 * $T4
    $Om = 124.7746 - 1.56375588 * $k + 0.0020672 * $T2 + 0.00000215 * $T3
    $E  = 1.0 - 0.002516 * $T - 0.0000074 * $T2

    $F1 = $F - 0.02665 * (SinD $Om)
    $A1 = 299.77 + 0.107408 * $k - 0.009173 * $T2

    $jde = 2451550.09766 + 29.530588861 * $k + 0.00015437 * $T2 - 0.000000150 * $T3 + 0.00000000073 * $T4

    $isSolar = [math]::Abs($k - [math]::Floor($k)) -lt 0.01

    $lead = if ($isSolar) { -0.4075 } else { -0.4065 }
    $lead2 = if ($isSolar) { 0.1721 } else { 0.1727 }

    $jde = $jde + $lead * (SinD $Mp) + $lead2 * $E * (SinD $M)
    $jde = $jde + 0.0161 * (SinD (2 * $Mp)) - 0.0097 * (SinD (2 * $F1))
    $jde = $jde + 0.0073 * $E * (SinD ($Mp - $M)) - 0.0050 * $E * (SinD ($Mp + $M))
    $jde = $jde - 0.0023 * (SinD ($Mp - 2 * $F1)) + 0.0021 * $E * (SinD (2 * $M))
    $jde = $jde + 0.0012 * (SinD ($Mp + 2 * $F1)) + 0.0006 * $E * (SinD (2 * $Mp + $M))
    $jde = $jde - 0.0004 * (SinD (3 * $Mp)) - 0.0003 * $E * (SinD ($M + 2 * $F1))
    $jde = $jde + 0.0003 * (SinD $A1) - 0.0002 * $E * (SinD ($M - 2 * $F1))
    $jde = $jde - 0.0002 * $E * (SinD (2 * $Mp - $M)) - 0.0002 * (SinD $Om)

    $P = 0.2070 * $E * (SinD $M) + 0.0024 * $E * (SinD (2 * $M))
    $P = $P - 0.0392 * (SinD $Mp) + 0.0116 * (SinD (2 * $Mp))
    $P = $P - 0.0073 * $E * (SinD ($Mp + $M)) + 0.0067 * $E * (SinD ($Mp - $M))
    $P = $P + 0.0118 * (SinD (2 * $F1))

    $Q = 5.2207 - 0.0048 * $E * (CosD $M) + 0.0020 * $E * (CosD (2 * $M))
    $Q = $Q - 0.3299 * (CosD $Mp) - 0.0060 * $E * (CosD ($Mp + $M))
    $Q = $Q + 0.0041 * $E * (CosD ($Mp - $M))

    $W     = [math]::Abs((CosD $F1))
    $gamma = ($P * (CosD $F1) + $Q * (SinD $F1)) * (1.0 - 0.0048 * $W)
    $u     = 0.0059 + 0.0046 * $E * (CosD $M) - 0.0182 * (CosD $Mp)
    $u     = $u + 0.0004 * (CosD (2 * $Mp)) - 0.0005 * (CosD ($M + $Mp))

    $ag = [math]::Abs($gamma)

    if ($isSolar) {
        if ($ag -gt 1.5433 + $u) { return $null }
        $type = 0                                  # partial
        if ($ag -lt 0.9972) {
            if ($u -lt 0)          { $type = 2 }   # total
            elseif ($u -gt 0.0047) { $type = 1 }   # annular
            else                   { $type = 3 }   # hybrid
        }
        # Meeus gives magnitude directly only for partial eclipses. A central
        # eclipse is by definition at or above unity, and the renderer keys off
        # the type anyway, so it is reported as 1.0 there.
        $mag = (1.5433 + $u - $ag) / (0.5461 + 2.0 * $u)
        if ($ag -lt 0.9972) { $mag = 1.0 }
        return @{ Jde = $jde; Kind = "solar"; Type = $type; Mag = $mag; Gamma = $gamma }
    }

    $umbral = (1.0128 - $u - $ag) / 0.5450
    $penum  = (1.5573 + $u - $ag) / 0.5450
    if ($penum -le 0) { return $null }
    $type = 4                                      # penumbral
    if ($umbral -ge 1.0)     { $type = 6 }         # total
    elseif ($umbral -gt 0.0) { $type = 5 }         # partial
    return @{ Jde = $jde; Kind = 'lunar'; Type = $type; Mag = $umbral; Gamma = $gamma }
}

# Any eclipse whose maximum is within the window of days-since-2000 instant $d.
function EclipseAt([double]$d) {
    $jd = $script:JD_2000 + $d
    $kApprox = ($jd - 2451550.09766) / 29.530588861
    $floor = [math]::Floor($kApprox)
    for ($i = -1; $i -le 1; $i++) {
        $ks = @(($floor + $i), ($floor + $i + 0.5))
        foreach ($k in $ks) {
            $e = EclipseForK $k
            if ($null -eq $e) { continue }
            if ([math]::Abs($e.Jde - $jd) -le $script:WINDOW) { return $e }
        }
    }
    return $null
}
