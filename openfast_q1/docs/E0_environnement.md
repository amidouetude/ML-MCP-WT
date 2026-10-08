# E0 — Environnement gelé (article unique OpenFAST)

Relevé du 08/10/2026 par l'exécutant (directive E0, action E0-1), en lecture seule de `C:\dev`.
Chaque valeur est suivie de la commande qui l'a produite.

## 1. Code source OpenFAST et dépôts associés

| Dépôt | Origine | Version | Commit (HEAD) | Date du commit | État de la copie de travail |
|---|---|---|---|---|---|
| `C:\dev\openfast-4.2.1` | github.com/OpenFAST/openfast | `v4.2.1-dirty` | `2daa99a0f9f573642816d6f52c07a2e3b77a85f1` | 2026-03-10 12:52:32 −0600 | une seule différence : le sous-module `reg_tests/r-test` (voir ligne suivante) |
| `C:\dev\openfast-4.2.1\reg_tests\r-test` | github.com/OpenFAST/r-test | `v4.2.0-dirty` | `6fda1b18fe6d720fdd47c6b18823b3a755cd004c` | 2026-01-27 15:16:35 −0700 | **13 différences**, détaillées ci-dessous |
| `C:\dev\matlab-toolbox` | github.com/OpenFAST/matlab-toolbox | `66256c2` | `66256c22c8e03a8c3591439af6dc09ee1219a932` | 2026-04-13 14:09:55 −0600 | propre |
| `C:\dev\wt-work` | — | pas un dépôt Git | — | — | — |

Commandes : `git -C <dépôt> describe --tags --always --dirty`, `git -C <dépôt> log -1 --format="%H %ad" --date=iso`, `git -C <dépôt> status --porcelain`, `git -C <dépôt> remote -v`.

**Différences de `r-test` par rapport à son commit** (`git status --porcelain`) :
- `M glue-codes/openfast/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.outb` : **la sortie de référence du cas `5MW_Land_DLL_WTurb` a été écrasée** par une exécution locale. La version d'origine reste lisible dans Git (`git show HEAD:<chemin>`). Elle ne doit pas être lue sur le disque.
- 12 fichiers non suivis : les fichiers `.sum` et `.ech` de `5MW_Land_DLL_WTurb`, et les sorties `AOC_WSt.SFunc.*`, traces de ces exécutions locales.
- Le cas `5MW_Land_AeroMap` n'a aucune différence.

`C:\dev\setup_openfast.m` est un fichier vide (0 octet).

## 2. Binaires (`C:\dev\openfast-bin`)

| Fichier | Taille (octets) | SHA-256 | Date (disque) |
|---|---:|---|---|
| `openfast_x64.exe` | 42 023 424 | `dbae80560269c00f4a1f3529b5bb3ffcd111faa6d6791f4cce6dcf321679d924` | 2026-09-17 14:44 |
| `TurbSim_x64.exe` | 22 106 624 | `5f70b3e2d50cbe09ad37d98569443a7d6f1b7a97c214bf21bbd9533cf2f29df2` | 2026-09-17 14:44 |
| `OpenFAST-Simulink_x64.dll` | 43 485 184 | `2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d` | 2026-09-17 14:44 |
| `FAST_SFunc.mexw64` | 148 992 | `16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297` | 2026-09-17 14:44 |
| `Discon.dll` | 514 560 | `787e43e89a864fe0fe26db5f9ab05ed29e62196b7c718c496e278a52effa0f7b` | 2026-09-17 14:44 |

Commandes : SHA-256 calculé par `java.security.MessageDigest` (MATLAB) ; taille et date par `dir`.

**`openfast_x64.exe -v`** : `OpenFAST-v4.2.1` ; compilateur Intel Fortran 20250300 ; 64 bits ; **précision simple** ; sans OpenMP ; compilé le 10/03/2026 à 20:35:11. Licence Apache 2.0.

**`TurbSim_x64.exe -v`** : `TurbSim-v4.2.1` ; mêmes options de compilation (précision simple, sans OpenMP), compilé le 10/03/2026 à 20:43:05.

**TurbSim est présent** dans `C:\dev\openfast-bin`. Il n'est pas dans le PATH (`where turbsim* openfast*` ne trouve rien). La décision « installer ou compiler TurbSim » devient sans objet ; reste à décider s'il est validé et utilisé tel quel.

## 3. Contrôleur `DISCON.dll`

Trois exemplaires, **identiques octet pour octet** (SHA-256 `787e43e89a864fe0fe26db5f9ab05ed29e62196b7c718c496e278a52effa0f7b`, 514 560 octets, daté du 2026-09-17 14:44) :
- `C:\dev\openfast-bin\Discon.dll` ;
- `C:\dev\openfast-4.2.1\reg_tests\r-test\glue-codes\openfast\5MW_Baseline\ServoData\DISCON.dll` (ignoré par Git : `.gitignore:19:*.dll`) ;
- `C:\dev\wt-work\5MW_Baseline\ServoData\DISCON.dll`.

**Origine :** la source du régulateur de base est suivie dans r-test, dans `5MW_Baseline/ServoData/DISCON/DISCON.F90` et son `CMakeLists.txt`. Aucun journal de compilation n'a été trouvé, donc **le lien entre ce DLL et cette source n'est pas établi** : origine non déterminée. Le DLL date du même jour que les autres binaires (17/09), ce qui suggère qu'il vient de la même distribution, sans le prouver.

Commande : `dir C:\dev\**\*iscon*.dll`, puis SHA-256 ; `git -C r-test ls-files .../ServoData` ; `git -C r-test check-ignore -v .../DISCON.dll`.

## 4. MATLAB

- Version : **MATLAB 24.1.0.2537033 (R2024a)** (`version`).
- Simulink 24.1 : **présent**.
- Boîtes à outils utiles au projet (`ver`) : Control System, Deep Learning, Model Predictive Control, Optimization, Global Optimization, Parallel Computing, Signal Processing, Statistics and Machine Learning, System Identification, Fuzzy Logic, Simulink Control Design, Simulink Design Optimization, Simscape, Simscape Driveline, Simscape Electrical, Simulink Coder, MATLAB Coder, Embedded Coder, toutes en version 24.1 (R2024a). Également installé : MATLAB MCP Server Toolbox 0.3.0.
- La liste complète (108 produits) est obtenue par `ver` ; elle est reproduite à l'annexe A.

## 5. Machine

Commande : `Get-CimInstance Win32_Processor`, `Win32_ComputerSystem`, `Win32_OperatingSystem` (PowerShell).

| Élément | Valeur |
|---|---|
| Processeur | 12th Gen Intel Core i5-12450H, 8 cœurs, 12 processeurs logiques, fréquence nominale 2,0 GHz |
| Mémoire | 16 905 461 760 octets (15,7 Gio) |
| Machine | CASPER EXCALIBUR G870 |
| Système | Microsoft Windows 11 Home Single Language, version 10.0.26300, 64 bits |

## 6. Cas r-test candidats (fichiers suivis : `git -C r-test ls-files <dossier>`)

**`glue-codes/openfast/5MW_Land_AeroMap`** : `5MW_Land_AeroMap.drv`, `5MW_Land_AeroMap.outb` (sortie de référence), `5MW_Land_DLL_WTurb.fst`, `NRELOffshrBsline5MW_Onshore_AeroDyn.dat`, `NRELOffshrBsline5MW_Onshore_ElastoDyn.dat`, `NRELOffshrBsline5MW_Onshore_ElastoDyn_Tower.dat`, `plotFASTAeroMap.m`.

**`glue-codes/openfast/5MW_Land_DLL_WTurb`** : `5MW_Land_DLL_WTurb.fst`, `5MW_Land_DLL_WTurb.log`, `5MW_Land_DLL_WTurb.outb` (sortie de référence, **modifiée sur le disque**), `NRELOffshrBsline5MW_Onshore_AeroDyn.dat`, `NRELOffshrBsline5MW_Onshore_ElastoDyn.dat`, `NRELOffshrBsline5MW_Onshore_ElastoDyn_Tower.dat`, `NRELOffshrBsline5MW_Onshore_ServoDyn.dat`, `README.md`.

**Fichiers de `5MW_Baseline` référencés par ces deux cas** (relevés dans les `.fst` et `.dat`) :
- `NRELOffshrBsline5MW_AeroDyn_blade.dat` et `Airfoils/` (Cylinder1, Cylinder2, DU21_A17, DU25_A17, DU30_A17, DU35_A17, DU40_A17, NACA64_A17) ;
- `NRELOffshrBsline5MW_Blade.dat` (ElastoDyn) ;
- `NRELOffshrBsline5MW_BeamDyn.dat` (référencé par le `.fst`) ;
- `NRELOffshrBsline5MW_InflowWind_12mps.dat` ;
- `ServoData/DISCON.dll` (cas `DLL_WTurb` seulement).

**`5MW_Baseline` complet** : 64 fichiers suivis, répartis ainsi :

| Dossier ou fichier | Fichiers |
|---|---:|
| `AeroData` | 8 |
| `Airfoils` | 16 |
| `HydroData` (offshore) | 17 |
| `ServoData` (sources DISCON, DISCON_ITI, DISCON_OC3) | 6 |
| `Wind` (dont `90m_12mps_twr.bts`, 8,3 Mo) | 4 |
| autres fichiers `.dat` et `.inp` | 13 |

## 7. Copie versionnée du modèle (action E0-2) et licence

**Licence.** Le dépôt r-test est distribué sous **licence Apache 2.0** (fichier `LICENSE` à sa racine). OpenFAST et TurbSim le sont aussi (sortie de `-v`). La copie de fichiers d'entrée de r-test dans ce dépôt est donc permise, à condition de conserver la mention de la licence et l'origine des fichiers, ce que fait cette section.

**Origine.** Les fichiers viennent de r-test au commit `6fda1b18fe6d720fdd47c6b18823b3a755cd004c`, dossier `glue-codes/openfast/`. Ils sont copiés sous `openfast_q1/model/` en conservant l'arborescence relative.

**Sélection : 50 fichiers sur les 79 suivis** des dossiers `5MW_Land_AeroMap`, `5MW_Land_DLL_WTurb` et `5MW_Baseline`.

Sont exclus :
- les sorties (`.outb`, `.log`, `.sum`) ;
- le champ de vent binaire (`.bts`) ;
- les fichiers offshore : `HydroData/`, `IceDyn_Input.dat`, `IceFloe_IEC_Crushing.dat`, `NRELOffshrBsline5MW_Monopile_IEC_Crushing.inp`, et les régulateurs `DISCON_ITI` et `DISCON_OC3`.

Aucun binaire n'est copié : `DISCON.dll` n'est pas suivi par r-test.

**Contrôle de conformité au commit.** Les 50 fichiers sont identiques au contenu du commit :
- 39 sont identiques octet pour octet (`git hash-object --no-filters`) ;
- 11 ne diffèrent que par les fins de ligne (CRLF sur le disque, LF dans le commit, `core.autocrlf=true`).

Les copies sont celles du disque, c'est-à-dire les fichiers qu'utilise l'installation. Leurs empreintes SHA-256 sont dans `openfast_q1/model/EMPREINTES_modele.sha256`.

**Limite connue.** Le cas `5MW_Land_DLL_WTurb` ne peut pas tourner à partir de cette seule copie. Il lui faut :
- le champ de vent `Wind/90m_12mps_twr.bts`, binaire de 8,3 Mo, non copié ;
- `ServoData/DISCON.dll`, binaire, non copié.

Ces deux fichiers restent dans `C:\dev`, avec leurs empreintes relevées aux sections 3 et 6.

## Annexe A — sortie de `ver` (MATLAB R2024a)

5G Toolbox, AUTOSAR Blockset, Aerospace Blockset, Aerospace Toolbox, Antenna Toolbox, Audio Toolbox, Automated Driving Toolbox, Bioinformatics Toolbox, Bluetooth Toolbox, C2000 Microcontroller Blockset, Communications Toolbox, Computer Vision Toolbox, Control System Toolbox, Curve Fitting Toolbox, DDS Blockset, DSP HDL Toolbox, DSP System Toolbox, Data Acquisition Toolbox, Database Toolbox, Datafeed Toolbox, Deep Learning HDL Toolbox, Deep Learning Toolbox, Econometrics Toolbox, Embedded Coder, Filter Design HDL Coder, Financial Instruments Toolbox, Financial Toolbox, Fixed-Point Designer, Fuzzy Logic Toolbox, GPU Coder, Global Optimization Toolbox, HDL Coder, HDL Verifier, Image Acquisition Toolbox, Image Processing Toolbox, Industrial Communication Toolbox, Instrument Control Toolbox, LTE Toolbox, Lidar Toolbox, MATLAB, MATLAB Coder, MATLAB Compiler, MATLAB Compiler SDK, MATLAB Report Generator, MATLAB Test, Mapping Toolbox, Medical Imaging Toolbox, Mixed-Signal Blockset, Model Predictive Control Toolbox, Model-Based Calibration Toolbox, Motor Control Blockset, Navigation Toolbox, Optimization Toolbox, Parallel Computing Toolbox, Partial Differential Equation Toolbox, Phased Array System Toolbox, Powertrain Blockset, Predictive Maintenance Toolbox, RF Blockset, RF PCB Toolbox, RF Toolbox, ROS Toolbox, Radar Toolbox, Reinforcement Learning Toolbox, Requirements Toolbox, Risk Management Toolbox, Robotics System Toolbox, Robust Control Toolbox, Satellite Communications Toolbox, Sensor Fusion and Tracking Toolbox, SerDes Toolbox, Signal Integrity Toolbox, Signal Processing Toolbox, SimBiology, SimEvents, Simscape, Simscape Battery, Simscape Driveline, Simscape Electrical, Simscape Fluids, Simscape Multibody, Simulink, Simulink 3D Animation, Simulink Check, Simulink Code Inspector, Simulink Coder, Simulink Compiler, Simulink Control Design, Simulink Coverage, Simulink Design Optimization, Simulink Design Verifier, Simulink Desktop Real-Time, Simulink Fault Analyzer, Simulink PLC Coder, Simulink Real-Time, Simulink Report Generator, Simulink Test, SoC Blockset, Spreadsheet Link, Stateflow, Statistics and Machine Learning Toolbox, Symbolic Math Toolbox, System Composer, System Identification Toolbox, Text Analytics Toolbox, UAV Toolbox, Vehicle Dynamics Blockset, Vehicle Network Toolbox, Vision HDL Toolbox, WLAN Toolbox, Wireless HDL Toolbox, Wireless Testbench — tous en version 24.1 (R2024a) ; MATLAB MCP Server Toolbox 0.3.0.
