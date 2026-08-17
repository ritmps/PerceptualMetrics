(* ::Package:: *)

BeginPackage["PerceptualMetrics`"];

StartPerceptualSession::usage = "StartPerceptualSession[] starts an ExternalSession for Python with lpips_bridge loaded.";
StopPerceptualSession::usage = "StopPerceptualSession[session] terminates the given python session.";
PerceptualInfo::usage = "PerceptualInfo[session] returns metadata about the PyTorch environment, device, and available metrics.";
PerceptualDistance::usage = "PerceptualDistance[session, img1, img2, opts] computes perceptual distance between two images.";
PerceptualDistanceBatch::usage = "PerceptualDistanceBatch[session, {{img1, img2}, ...}, opts] computes perceptual distances for a batch of image pairs.";
PerceptualDistanceArray::usage = "PerceptualDistanceArray[session, arr1, arr2, opts] computes perceptual distance between raw numeric arrays or images.";
PerceptualSpatialMap::usage = "PerceptualSpatialMap[session, img1, img2, opts] computes a spatial similarity map Image between two images.";

(* Backward-compatible LPIPS aliases *)
startLPIPSSession::usage = "startLPIPSSession[] alias for StartPerceptualSession[].";
lpipsInfo::usage = "lpipsInfo[session] alias for PerceptualInfo[session].";
lpipsDistance::usage = "lpipsDistance[session, img1, img2, opts] alias for PerceptualDistance[session, img1, img2, opts].";
lpipsDistanceBatch::usage = "lpipsDistanceBatch[session, pairs, opts] alias for PerceptualDistanceBatch[session, pairs, opts].";
lpipsDistanceArray::usage = "lpipsDistanceArray[session, arr1, arr2, opts] alias for PerceptualDistanceArray[session, arr1, arr2, opts].";
lpipsSpatialMap::usage = "lpipsSpatialMap[session, img1, img2, opts] alias for PerceptualSpatialMap[session, img1, img2, opts].";

Begin["`Private`"];

Options[PerceptualDistance] = {
    "Metric" -> "lpips",
    "Net" -> "alex",
    "Version" -> "0.1",
    "LPIPS" -> True,
    "ColorSpace" -> "Lab",
    "Spatial" -> False,
    "Device" -> Automatic
};

Options[PerceptualDistanceBatch] = Options[PerceptualDistance];
Options[PerceptualDistanceArray] = Options[PerceptualDistance];
Options[PerceptualSpatialMap] = Options[PerceptualDistance];

Options[lpipsDistance] = Options[PerceptualDistance];
Options[lpipsDistanceBatch] = Options[PerceptualDistance];
Options[lpipsDistanceArray] = Options[PerceptualDistance];
Options[lpipsSpatialMap] = Options[PerceptualDistance];

findVenvPython[] := Module[{dir, candidates, found},
    dir = DirectoryName[$InputFileName];
    If[dir === "" || !StringQ[dir], dir = Directory[]];
    candidates = {
        FileNameJoin[{dir, ".venv", "bin", "python"}],
        FileNameJoin[{ParentDirectory[dir], ".venv", "bin", "python"}],
        FileNameJoin[{dir, ".venv", "Scripts", "python.exe"}]
    };
    found = SelectFirst[candidates, FileExistsQ, None];
    If[found === None, "python", found]
];

findBridgeScript[] := Module[{dir, candidates, found},
    dir = DirectoryName[$InputFileName];
    If[dir === "" || !StringQ[dir], dir = Directory[]];
    candidates = {
        FileNameJoin[{dir, "lpips_bridge.py"}],
        FileNameJoin[{ParentDirectory[dir], "lpips_bridge.py"}]
    };
    found = SelectFirst[candidates, FileExistsQ, None];
    If[found === None,
        FileNameJoin[{Directory[], "lpips_bridge.py"}],
        found
    ]
];

StartPerceptualSession[opts___] := Module[{pythonPath, session, bridgePath},
    pythonPath = findVenvPython[];
    session = StartExternalSession[<|
        "System" -> "Python",
        "Executable" -> pythonPath
    |>];
    bridgePath = findBridgeScript[];
    If[FileExistsQ[bridgePath],
        ExternalEvaluate[session, File[bridgePath]],
        Message[StartPerceptualSession::nobridge, bridgePath]
    ];
    session
];

startLPIPSSession[opts___] := StartPerceptualSession[opts];

StopPerceptualSession[session_] := DeleteObject[session];

PerceptualInfo[session_] := ExternalEvaluate[session, <|
    "Command" -> "lpips_info",
    "Arguments" -> {}
|>];

lpipsInfo[session_] := PerceptualInfo[session];

withTemporaryPairFiles[image1_Image, image2_Image, body_] := Module[
    {dir, file1, file2, result},
    dir = CreateDirectory[FileNameJoin[{$TemporaryDirectory, CreateUUID["perceptual-"]}]];
    file1 = FileNameJoin[{dir, "image1.png"}];
    file2 = FileNameJoin[{dir, "image2.png"}];
    Export[file1, image1, "PNG"];
    Export[file2, image2, "PNG"];
    result = Check[body[file1, file2], $Failed];
    Quiet[DeleteDirectory[dir, DeleteContents -> True]];
    result
];

resolveDevice[dev_] := If[dev === Automatic || dev === None, None, ToString[dev]];

PerceptualDistance[session_, image1_Image, image2_Image, opts: OptionsPattern[]] := 
    withTemporaryPairFiles[
        ColorConvert[image1, "RGB"],
        ColorConvert[image2, "RGB"],
        Function[{file1, file2},
            ExternalEvaluate[session, <|
                "Command" -> "compute_distance",
                "Arguments" -> {
                    file1,
                    file2,
                    ToString[OptionValue["Metric"]],
                    ToString[OptionValue["Net"]],
                    ToString[OptionValue["Version"]],
                    TrueQ[OptionValue["Spatial"]],
                    resolveDevice[OptionValue["Device"]],
                    TrueQ[OptionValue["LPIPS"]],
                    ToString[OptionValue["ColorSpace"]]
                }
            |>]
        ]
    ];

lpipsDistance[session_, image1_Image, image2_Image, opts: OptionsPattern[]] := 
    PerceptualDistance[session, image1, image2, opts];

PerceptualDistanceBatch[session_, imagePairs: {{_Image, _Image}...}, opts: OptionsPattern[]] := Module[
    {dir, pathPairs, result},
    dir = CreateDirectory[FileNameJoin[{$TemporaryDirectory, CreateUUID["perceptual-batch-"]}]];
    pathPairs = MapIndexed[
        Module[{f1 = FileNameJoin[{dir, "img1_" <> ToString[#2[[1]]] <> ".png"}],
                f2 = FileNameJoin[{dir, "img2_" <> ToString[#2[[1]]] <> ".png"}]},
            Export[f1, ColorConvert[#1[[1]], "RGB"], "PNG"];
            Export[f2, ColorConvert[#1[[2]], "RGB"], "PNG"];
            {f1, f2}
        ]&,
        imagePairs
    ];
    result = ExternalEvaluate[session, <|
        "Command" -> "lpips_distance_batch",
        "Arguments" -> {
            pathPairs,
            ToString[OptionValue["Net"]],
            ToString[OptionValue["Version"]],
            TrueQ[OptionValue["Spatial"]],
            resolveDevice[OptionValue["Device"]],
            TrueQ[OptionValue["LPIPS"]],
            ToString[OptionValue["Metric"]],
            ToString[OptionValue["ColorSpace"]]
        }
    |>];
    Quiet[DeleteDirectory[dir, DeleteContents -> True]];
    result
];

lpipsDistanceBatch[session_, imagePairs_, opts: OptionsPattern[]] := 
    PerceptualDistanceBatch[session, imagePairs, opts];

toRGBArray[img_Image] := ImageData[ColorConvert[img, "RGB"], "Real"];
toRGBArray[arr_] := arr;

PerceptualDistanceArray[session_, arr1_, arr2_, opts: OptionsPattern[]] := Module[
    {a1 = toRGBArray[arr1], a2 = toRGBArray[arr2], rawRes},
    rawRes = ExternalEvaluate[session, <|
        "Command" -> "compute_distance",
        "Arguments" -> {
            a1,
            a2,
            ToString[OptionValue["Metric"]],
            ToString[OptionValue["Net"]],
            ToString[OptionValue["Version"]],
            TrueQ[OptionValue["Spatial"]],
            resolveDevice[OptionValue["Device"]],
            TrueQ[OptionValue["LPIPS"]],
            ToString[OptionValue["ColorSpace"]]
        }
    |>];
    If[TrueQ[OptionValue["Spatial"]] && ArrayQ[rawRes],
        Image[rawRes, "Real"],
        rawRes
    ]
];

lpipsDistanceArray[session_, arr1_, arr2_, opts: OptionsPattern[]] := 
    PerceptualDistanceArray[session, arr1, arr2, opts];

PerceptualSpatialMap[session_, image1_Image, image2_Image, opts: OptionsPattern[]] := Module[
    {rawMap},
    rawMap = withTemporaryPairFiles[
        ColorConvert[image1, "RGB"],
        ColorConvert[image2, "RGB"],
        Function[{file1, file2},
            ExternalEvaluate[session, <|
                "Command" -> "lpips_distance_spatial",
                "Arguments" -> {
                    file1,
                    file2,
                    ToString[OptionValue["Net"]],
                    ToString[OptionValue["Version"]],
                    resolveDevice[OptionValue["Device"]],
                    TrueQ[OptionValue["LPIPS"]],
                    ToString[OptionValue["Metric"]],
                    ToString[OptionValue["ColorSpace"]]
                }
            |>]
        ]
    ];
    If[ArrayQ[rawMap], Image[rawMap, "Real"], rawMap]
];

lpipsSpatialMap[session_, image1_Image, image2_Image, opts: OptionsPattern[]] := 
    PerceptualSpatialMap[session, image1, image2, opts];

End[];
EndPackage[];
