(* ::Package:: *)

BeginPackage["PerceptualMetrics`"];

StartPerceptualSession::usage = "StartPerceptualSession[] starts an ExternalSession for Python with lpips_bridge loaded.";

StopPerceptualSession::usage = "StopPerceptualSession[] or StopPerceptualSession[session] terminates the background or specified Python session.";

PerceptualInfo::usage = "PerceptualInfo[] or PerceptualInfo[session] returns metadata about PyTorch, device, and available metrics.";

PerceptualDistance::usage = "PerceptualDistance[img1, img2, opts] computes perceptual or dissimilarity distance between images, image pairs, or numeric arrays.";

PerceptualSpatialMap::usage = "PerceptualSpatialMap[img1, img2, opts] computes a 2D spatial similarity map Image between two images.";

$DefaultPerceptualSession::usage = "$DefaultPerceptualSession holds the automatically managed background Python session.";

Begin["`Private`"];

Options[PerceptualDistance] = {"Metric" -> "lpips", "Net" -> "alex", 
    "Version" -> "0.1", "LPIPS" -> True, "ColorSpace" -> "Lab", "Spatial"
     -> False, "Device" -> Automatic};

Options[PerceptualSpatialMap] = Options[PerceptualDistance];

$DefaultPerceptualSession = None;

findVenvPython[] :=
    Module[{dir, candidates, found},
        dir = DirectoryName[$InputFileName];
        If[dir === "" || !StringQ[dir],
            dir = Directory[]
        ];
        candidates = {FileNameJoin[{dir, ".venv", "bin", "python"}], 
            FileNameJoin[{ParentDirectory[dir], ".venv", "bin", "python"}], FileNameJoin[
            {dir, ".venv", "Scripts", "python.exe"}]};
        found = SelectFirst[candidates, FileExistsQ, None];
        If[found === None,
            "python"
            ,
            found
        ]
    ];

findBridgeScript[] :=
    Module[{dir, candidates, found},
        dir = DirectoryName[$InputFileName];
        If[dir === "" || !StringQ[dir],
            dir = Directory[]
        ];
        candidates = {FileNameJoin[{dir, "lpips_bridge.py"}], FileNameJoin[
            {ParentDirectory[dir], "lpips_bridge.py"}]};
        found = SelectFirst[candidates, FileExistsQ, None];
        If[found === None,
            FileNameJoin[{Directory[], "lpips_bridge.py"}]
            ,
            found
        ]
    ];

StartPerceptualSession[opts___] :=
    Module[{pythonPath, session, bridgePath},
        pythonPath = findVenvPython[];
        session = StartExternalSession[<|"System" -> "Python", "Executable"
             -> pythonPath|>];
        bridgePath = findBridgeScript[];
        If[FileExistsQ[bridgePath],
            ExternalEvaluate[session, File[bridgePath]]
            ,
            Message[StartPerceptualSession::nobridge, bridgePath]
        ];
        session
    ];

$kernelExitRegistered = False;

registerKernelExitCleanup[] :=
    If[!$kernelExitRegistered,
        $kernelExitRegistered = True;
        If[NameQ["System`AddHandler"],
            Quiet[AddHandler["KernelExit", Function[StopPerceptualSession[
                ]]]]
        ];
        If[!ValueQ[$Epilog],
            $Epilog = (StopPerceptualSession[];)
        ];
        If[FreeQ[$Epilog, StopPerceptualSession],
            $Epilog = CompoundExpression[HoldPattern[StopPerceptualSession[
                ]], $Epilog]
        ];
    ];

sessionValidQ[session_ExternalSessionObject] :=
    TrueQ[Quiet[Check[StringQ[ExternalEvaluate[session, "'ok'"]], False
        ]]];

sessionValidQ[___] :=
    False;

ensureSession[session_ExternalSessionObject] :=
    session;

ensureSession[___] :=
    Module[{},
        If[!sessionValidQ[$DefaultPerceptualSession],
            StopPerceptualSession[];
            $DefaultPerceptualSession = StartPerceptualSession[];
            registerKernelExitCleanup[];
        ];
        $DefaultPerceptualSession
    ];

StopPerceptualSession[] :=
    Module[{},
        If[MatchQ[$DefaultPerceptualSession, _ExternalSessionObject],
            
            Quiet[DeleteObject[$DefaultPerceptualSession]];
            $DefaultPerceptualSession = None;
        ];
    ];

StopPerceptualSession[session_ExternalSessionObject] :=
    (
        If[session === $DefaultPerceptualSession,
            $DefaultPerceptualSession = None
        ];
        Quiet[DeleteObject[session]]
    );

PerceptualInfo[session_ExternalSessionObject] :=
    ExternalEvaluate[session, <|"Command" -> "lpips_info", "Arguments"
         -> {}|>];

PerceptualInfo[] :=
    PerceptualInfo[ensureSession[]];

withTemporaryPairFiles[image1_Image, image2_Image, body_] :=
    Module[{dir, file1, file2, result},
        dir = CreateDirectory[FileNameJoin[{$TemporaryDirectory, CreateUUID[
            "perceptual-"]}]];
        file1 = FileNameJoin[{dir, "image1.png"}];
        file2 = FileNameJoin[{dir, "image2.png"}];
        Export[file1, image1, "PNG"];
        Export[file2, image2, "PNG"];
        result = Check[body[file1, file2], $Failed];
        Quiet[DeleteDirectory[dir, DeleteContents -> True]];
        result
    ];

resolveDevice[dev_] :=
    If[dev === Automatic || dev === None,
        None
        ,
        ToString[dev]
    ];

(* Single Image Pair Distance - Explicit Session *)

PerceptualDistance[session_ExternalSessionObject, image1_Image, image2_Image,
     opts : OptionsPattern[]] :=
    withTemporaryPairFiles[
        ColorConvert[image1, "RGB"]
        ,
        ColorConvert[image2, "RGB"]
        ,
        Function[{file1, file2},
            ExternalEvaluate[session, <|"Command" -> "compute_distance",
                 "Arguments" -> {file1, file2, ToString[OptionValue["Metric"]], ToString[
                OptionValue["Net"]], ToString[OptionValue["Version"]], TrueQ[OptionValue[
                "Spatial"]], resolveDevice[OptionValue["Device"]], TrueQ[OptionValue[
                "LPIPS"]], ToString[OptionValue["ColorSpace"]]}|>]
        ]
    ];

(* Batch Distance - Explicit Session *)

PerceptualDistance[session_ExternalSessionObject, imagePairs : {{_Image,
     _Image}...}, opts : OptionsPattern[]] :=
    Module[{dir, pathPairs, result},
        dir = CreateDirectory[FileNameJoin[{$TemporaryDirectory, CreateUUID[
            "perceptual-batch-"]}]];
        pathPairs =
            MapIndexed[
                Module[{f1 = FileNameJoin[{dir, "img1_" <> ToString[#2
                    [[1]]] <> ".png"}], f2 = FileNameJoin[{dir, "img2_" <> ToString[#2[[1
                    ]]] <> ".png"}]},
                    Export[f1, ColorConvert[#1[[1]], "RGB"], "PNG"];
                    Export[f2, ColorConvert[#1[[2]], "RGB"], "PNG"];
                    {f1, f2}
                ]&
                ,
                imagePairs
            ];
        result = ExternalEvaluate[session, <|"Command" -> "lpips_distance_batch",
             "Arguments" -> {pathPairs, ToString[OptionValue["Net"]], ToString[OptionValue[
            "Version"]], TrueQ[OptionValue["Spatial"]], resolveDevice[OptionValue[
            "Device"]], TrueQ[OptionValue["LPIPS"]], ToString[OptionValue["Metric"
            ]], ToString[OptionValue["ColorSpace"]]}|>];
        Quiet[DeleteDirectory[dir, DeleteContents -> True]];
        result
    ];

toRGBArray[img_Image] :=
    ImageData[ColorConvert[img, "RGB"], "Real"];

toRGBArray[arr_] :=
    arr;

(* Array Distance - Explicit Session *)

PerceptualDistance[session_ExternalSessionObject, arr1_, arr2_, opts 
    : OptionsPattern[]] :=
    Module[{a1 = toRGBArray[arr1], a2 = toRGBArray[arr2], rawRes},
        rawRes = ExternalEvaluate[session, <|"Command" -> "compute_distance",
             "Arguments" -> {a1, a2, ToString[OptionValue["Metric"]], ToString[OptionValue[
            "Net"]], ToString[OptionValue["Version"]], TrueQ[OptionValue["Spatial"
            ]], resolveDevice[OptionValue["Device"]], TrueQ[OptionValue["LPIPS"]],
             ToString[OptionValue["ColorSpace"]]}|>];
        If[TrueQ[OptionValue["Spatial"]] && (ArrayQ[rawRes] || NumericArrayQ[
            rawRes]),
            Image[rawRes]
            ,
            rawRes
        ]
    ];

(* Implicit Session Overloads *)

PerceptualDistance[image1_Image, image2_Image, opts : OptionsPattern[
    ]] :=
    PerceptualDistance[ensureSession[], image1, image2, opts];

PerceptualDistance[imagePairs : {{_Image, _Image}...}, opts : OptionsPattern[
    ]] :=
    PerceptualDistance[ensureSession[], imagePairs, opts];

PerceptualDistance[arr1_, arr2_, opts : OptionsPattern[]] :=
    PerceptualDistance[ensureSession[], arr1, arr2, opts];

(* Spatial Map - Explicit Session *)

PerceptualSpatialMap[session_ExternalSessionObject, image1_Image, image2_Image,
     opts : OptionsPattern[]] :=
    Module[{rawMap},
        rawMap =
            withTemporaryPairFiles[
                ColorConvert[image1, "RGB"]
                ,
                ColorConvert[image2, "RGB"]
                ,
                Function[{file1, file2},
                    ExternalEvaluate[session, <|"Command" -> "compute_distance",
                         "Arguments" -> {
                             file1,
                             file2,
                             ToString[OptionValue["Metric"]],
                             ToString[OptionValue["Net"]],
                             ToString[OptionValue["Version"]],
                             True,
                             resolveDevice[OptionValue["Device"]],
                             TrueQ[OptionValue["LPIPS"]],
                             ToString[OptionValue["ColorSpace"]]
                         }|>]
                ]
            ];
        If[ArrayQ[rawMap] || NumericArrayQ[rawMap],
            Image[rawMap]
            ,
            rawMap
        ]
    ];

(* Spatial Map - Implicit Session *)

PerceptualSpatialMap[image1_Image, image2_Image, opts : OptionsPattern[
    ]] :=
    PerceptualSpatialMap[ensureSession[], image1, image2, opts];

End[];

EndPackage[];
