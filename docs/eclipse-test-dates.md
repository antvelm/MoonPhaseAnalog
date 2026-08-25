# Eclipse test dates, 2025-2045

Human-readable form of `source/EclipseData.mc`, which is generated from
`docs/eclipse-events.tsv` by `tools/gen-eclipse-data.ps1`. Source: the NASA
GSFC eclipse catalogue (eclipse.gsfc.nasa.gov).

Use this as the manual test script: set the simulator clock with
**Settings > Time** to a row's UTC maximum, and the face should show that
eclipse. Penumbral lunar eclipses are detected but deliberately **not**
rendered -- they look like nothing in the sky, so they must leave the moon its
normal colour.

To exercise the rendering without hunting for a date, use the **Force eclipse**
setting instead. To check the location gate, set **Test latitude** and **Test
longitude** and park the clock on a lunar maximum: a night-side location shows
the red moon, its antipode does not.

| Date | Max (UTC) | Type | Magnitude | Shown as |
|---|---|---|---|---|
| 2025-03-14 | 06:59:56 | Total lunar | 1.178 | red moon |
| 2025-03-29 | 10:48:36 | Partial solar | 0.938 | corona |
| 2025-09-07 | 18:12:58 | Total lunar | 1.362 | red moon |
| 2025-09-21 | 19:43:04 | Partial solar | 0.855 | corona |
| 2026-02-17 | 12:13:05 | Annular solar | 0.963 | corona |
| 2026-03-03 | 11:34:52 | Total lunar | 1.151 | red moon |
| 2026-08-12 | 17:47:05 | Total solar | 1.039 | corona |
| 2026-08-28 | 04:14:04 | Partial lunar | 0.930 | red moon |
| 2027-02-06 | 16:00:47 | Annular solar | 0.928 | corona |
| 2027-02-20 | 23:14:06 | Penumbral lunar | -0.057 | no (penumbral) |
| 2027-07-18 | 16:04:09 | Penumbral lunar | -1.068 | no (penumbral) |
| 2027-08-02 | 10:07:49 | Total solar | 1.079 | corona |
| 2027-08-17 | 07:14:59 | Penumbral lunar | -0.525 | no (penumbral) |
| 2028-01-12 | 04:14:13 | Partial lunar | 0.066 | red moon |
| 2028-01-26 | 15:08:58 | Annular solar | 0.921 | corona |
| 2028-07-06 | 18:20:57 | Partial lunar | 0.389 | red moon |
| 2028-07-22 | 02:56:39 | Total solar | 1.056 | corona |
| 2028-12-31 | 16:53:15 | Total lunar | 1.246 | red moon |
| 2029-01-14 | 17:13:47 | Partial solar | 0.871 | corona |
| 2029-06-12 | 04:06:13 | Partial solar | 0.458 | corona |
| 2029-06-26 | 03:23:22 | Total lunar | 1.844 | red moon |
| 2029-07-11 | 15:37:18 | Partial solar | 0.230 | corona |
| 2029-12-05 | 15:03:57 | Partial solar | 0.891 | corona |
| 2029-12-20 | 22:43:12 | Total lunar | 1.117 | red moon |
| 2030-06-01 | 06:29:13 | Annular solar | 0.944 | corona |
| 2030-06-15 | 18:34:34 | Partial lunar | 0.502 | red moon |
| 2030-11-25 | 06:51:37 | Total solar | 1.047 | corona |
| 2030-12-09 | 22:28:51 | Penumbral lunar | -0.163 | no (penumbral) |
| 2031-05-07 | 03:52:02 | Penumbral lunar | -0.090 | no (penumbral) |
| 2031-05-21 | 07:16:04 | Annular solar | 0.959 | corona |
| 2031-06-05 | 11:45:17 | Penumbral lunar | -0.820 | no (penumbral) |
| 2031-10-30 | 07:46:45 | Penumbral lunar | -0.320 | no (penumbral) |
| 2031-11-14 | 21:07:30 | Hybrid solar | 1.011 | corona |
| 2032-04-25 | 15:14:51 | Total lunar | 1.191 | red moon |
| 2032-05-09 | 13:26:42 | Annular solar | 0.996 | corona |
| 2032-10-18 | 19:03:40 | Total lunar | 1.103 | red moon |
| 2032-11-03 | 05:34:12 | Partial solar | 0.855 | corona |
| 2033-03-30 | 18:02:35 | Total solar | 1.046 | corona |
| 2033-04-14 | 19:13:51 | Total lunar | 1.094 | red moon |
| 2033-09-23 | 13:54:31 | Partial solar | 0.689 | corona |
| 2033-10-08 | 10:56:23 | Total lunar | 1.350 | red moon |
| 2034-03-20 | 10:18:45 | Total solar | 1.046 | corona |
| 2034-04-03 | 19:06:59 | Penumbral lunar | -0.227 | no (penumbral) |
| 2034-09-12 | 16:19:27 | Annular solar | 0.974 | corona |
| 2034-09-28 | 02:47:37 | Partial lunar | 0.014 | red moon |
| 2035-02-22 | 09:06:12 | Penumbral lunar | -0.053 | no (penumbral) |
| 2035-03-09 | 23:05:53 | Annular solar | 0.992 | corona |
| 2035-08-19 | 01:12:15 | Partial lunar | 0.104 | red moon |
| 2035-09-02 | 01:56:46 | Total solar | 1.032 | corona |
| 2036-02-11 | 22:13:06 | Total lunar | 1.299 | red moon |
| 2036-02-27 | 04:46:49 | Partial solar | 0.629 | corona |
| 2036-07-23 | 10:32:06 | Partial solar | 0.199 | corona |
| 2036-08-07 | 02:52:32 | Total lunar | 1.454 | red moon |
| 2036-08-21 | 17:25:45 | Partial solar | 0.862 | corona |
| 2037-01-16 | 09:48:55 | Partial solar | 0.705 | corona |
| 2037-01-31 | 14:01:38 | Total lunar | 1.207 | red moon |
| 2037-07-13 | 02:40:35 | Total solar | 1.041 | corona |
| 2037-07-27 | 04:09:53 | Partial lunar | 0.809 | red moon |
| 2038-01-05 | 13:47:10 | Annular solar | 0.973 | corona |
| 2038-01-21 | 03:49:52 | Penumbral lunar | -0.114 | no (penumbral) |
| 2038-06-17 | 02:45:02 | Penumbral lunar | -0.527 | no (penumbral) |
| 2038-07-02 | 13:32:54 | Annular solar | 0.991 | corona |
| 2038-07-16 | 11:35:56 | Penumbral lunar | -0.495 | no (penumbral) |
| 2038-12-11 | 17:45:00 | Penumbral lunar | -0.289 | no (penumbral) |
| 2038-12-26 | 01:00:10 | Total solar | 1.027 | corona |
| 2039-06-06 | 18:54:25 | Partial lunar | 0.885 | red moon |
| 2039-06-21 | 17:12:53 | Annular solar | 0.945 | corona |
| 2039-11-30 | 16:56:28 | Partial lunar | 0.943 | red moon |
| 2039-12-15 | 16:23:46 | Total solar | 1.036 | corona |
| 2040-05-11 | 03:43:02 | Partial solar | 0.531 | corona |
| 2040-05-26 | 11:46:22 | Total lunar | 1.535 | red moon |
| 2040-11-04 | 19:09:01 | Partial solar | 0.807 | corona |
| 2040-11-18 | 19:04:41 | Total lunar | 1.397 | red moon |
| 2041-04-30 | 11:52:20 | Total solar | 1.019 | corona |
| 2041-05-16 | 00:43:03 | Partial lunar | 0.064 | red moon |
| 2041-10-25 | 01:36:21 | Annular solar | 0.947 | corona |
| 2041-11-08 | 04:35:05 | Partial lunar | 0.170 | red moon |
| 2042-04-05 | 14:30:11 | Penumbral lunar | -0.218 | no (penumbral) |
| 2042-04-20 | 02:17:30 | Total solar | 1.061 | corona |
| 2042-09-29 | 10:45:47 | Penumbral lunar | -0.003 | no (penumbral) |
| 2042-10-14 | 02:00:41 | Annular solar | 0.930 | corona |
| 2043-03-25 | 14:32:04 | Total lunar | 1.114 | red moon |
| 2043-04-09 | 18:57:49 | Total solar | 1.010 | corona |
| 2043-09-19 | 01:51:50 | Total lunar | 1.256 | red moon |
| 2043-10-03 | 03:01:48 | Annular solar | 0.950 | corona |
| 2044-02-28 | 20:24:39 | Annular solar | 0.960 | corona |
| 2044-03-13 | 19:38:33 | Total lunar | 1.203 | red moon |
| 2044-08-23 | 01:17:01 | Total solar | 1.036 | corona |
| 2044-09-07 | 11:20:44 | Total lunar | 1.046 | red moon |
| 2045-02-16 | 23:56:06 | Annular solar | 0.928 | corona |
| 2045-03-03 | 07:43:26 | Penumbral lunar | -0.017 | no (penumbral) |
| 2045-08-12 | 17:42:39 | Total solar | 1.077 | corona |
| 2045-08-27 | 13:54:50 | Penumbral lunar | -0.392 | no (penumbral) |

## Validation of the computed fallback

Past 2045 the face computes eclipses on the watch (Meeus, *Astronomical
Algorithms* 2nd ed., ch. 49 and 54). `tools/check-eclipse-math.ps1` runs that
same algorithm over every row above and diffs it against the table:

| Check | Result |
|---|---|
| Events detected | 92 / 93 |
| Correct type | 89 / 92 |
| Max timing error | 1.1 min |
| Max lunar magnitude error | 0.011 |
| False positives | 0 of 14945 samples |

The single miss is 2027-07-18, a very shallow penumbral eclipse that falls
outside Meeus' node test; it is not rendered either way. The three type
disagreements are all boundary cases (annular vs hybrid, total vs partial)
where gamma sits within a thousandth of the limit.

The on-watch unit tests in `source/EclipseTest.mc` assert the same properties
against the real Monkey C implementation, driven off every row of the table.
Run them with `tools\run-tests.ps1`.