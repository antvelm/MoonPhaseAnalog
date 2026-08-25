using Toybox.Lang;

// GENERATED FILE -- do not edit by hand.
// Regenerate with:  powershell -File tools\gen-eclipse-data.ps1
// Source of truth:  docs\eclipse-events.tsv (NASA GSFC eclipse catalogue)
//
// Every solar and lunar eclipse from 2025-03-14 to 2045-08-27 (93 events), stored as
// three flat parallel arrays. Flat Number arrays rather than an array of arrays:
// nested arrays each carry object overhead in Monkey C, and this table is
// resident for the life of the watch face.
module EclipseData {

    // Eclipse type codes, also the high digits of TYPEMAG.
    const PARTIAL_SOLAR  = 0;
    const ANNULAR        = 1;
    const TOTAL_SOLAR    = 2;
    const HYBRID         = 3;
    const PENUMBRAL      = 4;
    const PARTIAL_LUNAR  = 5;
    const TOTAL_LUNAR    = 6;

    // Days from 2000-01-01 UTC to the instant of greatest eclipse. Ascending.
    const DAYS = [
        9204, 9219, 9381, 9395, 9544, 9558, 9720, 9736, 9898, 9912, 10060, 10075, 
        10090, 10238, 10252, 10414, 10430, 10592, 10606, 10755, 10769, 10784, 10931, 10946, 
        11109, 11123, 11286, 11300, 11449, 11463, 11478, 11625, 11640, 11803, 11817, 11979, 
        11995, 12142, 12157, 12319, 12334, 12497, 12511, 12673, 12689, 12836, 12851, 13014, 
        13028, 13190, 13206, 13353, 13368, 13382, 13530, 13545, 13708, 13722, 13884, 13900, 
        14047, 14062, 14076, 14224, 14239, 14401, 14416, 14578, 14593, 14741, 14756, 14918, 
        14932, 15095, 15111, 15273, 15287, 15435, 15450, 15612, 15627, 15789, 15804, 15967, 
        15981, 16129, 16143, 16306, 16321, 16483, 16498, 16660, 16675
    ];

    // Minute of day (UTC) of greatest eclipse, 0..1439.
    const MINUTES = [
        419, 648, 1092, 1183, 733, 694, 1067, 254, 960, 1394, 964, 607, 434, 254, 908, 1100, 
        176, 1013, 1033, 246, 203, 937, 903, 1363, 389, 1114, 411, 1348, 232, 436, 705, 466, 
        1267, 914, 806, 1143, 334, 1082, 1153, 834, 656, 618, 1146, 979, 167, 546, 1385, 72, 
        116, 1333, 286, 632, 172, 1045, 588, 841, 160, 249, 827, 229, 165, 812, 695, 1065, 
        60, 1134, 1032, 1016, 983, 223, 706, 1149, 1144, 712, 43, 96, 275, 870, 137, 645, 
        120, 872, 1137, 111, 181, 1224, 1178, 77, 680, 1436, 463, 1062, 834
    ];

    // type * 1000 + round(magnitude * 100). Penumbral lunar magnitudes are
    // negative by definition and are stored as 0.
    const TYPEMAG = [
        6118, 94, 6136, 86, 1096, 6115, 2104, 5093, 1093, 4000, 4000, 2108, 
        4000, 5007, 1092, 5039, 2106, 6125, 87, 46, 6184, 23, 89, 6112, 
        1094, 5050, 2105, 4000, 4000, 1096, 4000, 4000, 3101, 6119, 1100, 6110, 
        86, 2105, 6109, 69, 6135, 2105, 4000, 1097, 5001, 4000, 1099, 5010, 
        2103, 6130, 63, 20, 6145, 86, 70, 6121, 2104, 5081, 1097, 4000, 
        4000, 1099, 4000, 4000, 2103, 5088, 1094, 5094, 2104, 53, 6154, 81, 
        6140, 2102, 5006, 1095, 5017, 4000, 2106, 4000, 1093, 6111, 2101, 6126, 
        1095, 1096, 6120, 2104, 6105, 1093, 4000, 2108, 4000
    ];

    const COUNT      = 93;
    const FIRST_DAY  = 9204;
    const LAST_DAY   = 16675;
    const LAST_LABEL = "2045-08-27";

    function isSolar(type) {
        return type <= HYBRID;
    }

    function isLunar(type) {
        return type >= PENUMBRAL;
    }
}