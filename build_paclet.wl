(* ::Package:: *)
(* Script to package PerceptualMetrics into a standalone .paclet archive *)

dir = DirectoryName[$InputFileName];
If[dir === "" || !StringQ[dir], dir = Directory[]];

Print["Building Paclet from directory: ", dir];

If[!FileExistsQ[FileNameJoin[{dir, "PacletInfo.wl"}]],
  Print["Error: PacletInfo.wl not found in ", dir];
  Exit[1];
];

(* Create a clean staging directory *)
buildDir = FileNameJoin[{dir, "build", "PerceptualMetrics"}];
distDir = FileNameJoin[{dir, "dist"}];

Quiet[DeleteDirectory[FileNameJoin[{dir, "build"}], DeleteContents -> True]];
Quiet[CreateDirectory[distDir]];
CreateDirectory[buildDir];

(* Copy necessary paclet files *)
filesToCopy = {"PacletInfo.wl", "PerceptualMetrics.wl", "lpips_bridge.py", "README.md"};
Do[
  src = FileNameJoin[{dir, f}];
  If[FileExistsQ[src],
    CopyFile[src, FileNameJoin[{buildDir, f}]]
  ]
  ,
  {f, filesToCopy}
];

(* Copy PerceptualSimilarity submodule excluding git metadata and cache *)
simSrc = FileNameJoin[{dir, "PerceptualSimilarity"}];
simDst = FileNameJoin[{buildDir, "PerceptualSimilarity"}];
If[DirectoryQ[simSrc],
  CopyDirectory[simSrc, simDst];
  Quiet[DeleteDirectory[FileNameJoin[{simDst, ".git"}], DeleteContents -> True]];
  Quiet[DeleteDirectory[FileNameJoin[{simDst, "__pycache__"}], DeleteContents -> True]];
];

Print["Staged paclet files in: ", buildDir];

(* Create paclet archive *)
archive = Quiet[Check[CreatePacletArchive[buildDir, distDir], $Failed]];

If[StringQ[archive] && FileExistsQ[archive],
  Print["\n=== Paclet Archive Created Successfully ==="];
  Print["Archive file: ", archive];
  Print["\nTo install on another machine, run in Wolfram Language:"];
  Print["  PacletInstall[\"", archive, "\"]"];
  ,
  Print["Error: Could not create paclet archive."];
  Exit[1];
];

(* Clean up staging directory *)
Quiet[DeleteDirectory[FileNameJoin[{dir, "build"}], DeleteContents -> True]];
