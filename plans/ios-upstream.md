# iOS sans Mac : contributions en amont et nettoyage de dev-box

État au 6/11/2026, midi. dev-box v1.54 épingle omarchy-apple-dev `v0.4.4` (`OAD_TAG` dans
`rootfs/usr/share/devbox/dev-envs/ios.sh`) ; omarchy y épingle son fork xtool `bfa69bf` (1.23.0 plus ses
correctifs).

Des contournements ont été ajoutés dans `devbox ios xcode` / `devbox ios kmp` pour construire Aero
(application-ios) et l'app KMP (application-android/iosApp). Chacun a été proposé en amont. Une fois les
correctifs publiés, dev-box peut les retirer.

## 1. Tickets et pull requests

### omarchy-apple-dev (joshuaswarren/omarchy-apple-dev)

| Ticket | PR | Sujet | État |
|---|---|---|---|
| #124 | #125 | `xcodeproj2xtool.py --configuration` (Debug, etc.) | ✅ fusionnée |
| #126 | #127 | Raccourcis d'assets `Color.x`, `UIColor(.x)`, `Image.x` | ✅ fusionnée |
| #128 | #129 | Info.plist du bundle de ressources (SwiftGen, `ship.sh --device`) | ✅ fusionnée |
| #130 | #131 | `tools/host-manifests.py` (RxSwift / `canImport(Darwin)`) | ✅ fusionnée |
| #133 | #134 | `kmp/build-framework.sh` (framework Kotlin lié sous Linux) | ✅ fusionnée |
| #132 | #135 | xtool épinglé : passage à 1.24.0 plus les correctifs du fork | ✅ fusionnée le 5/11 à 23 h 48 (squash 7ce8f58), pin `a8a5a40`, tag `omarchy-1.24.0-pin` du fork |
| | joshuaswarren/xtool#3 | Branche 1.24.0 plus les 11 commits du fork (pour `omarchy/1.24.0-fixes`) | ⏳ ouverte (le pin de main est déjà ce commit) |
| #132 | **#138** | xtool épinglé : main d'xtool (`4ec0e96`, contient #375, #430, #422) plus le contournement #432 et les 11 commits du fork (pin `86925e8`) | ⏳ ouverte (6/11, mise à jour le même jour) |
|  | joshuaswarren/xtool#4 | Maintenant main + #432 + fork (`86925e8`), à proposer comme nouveau pin quand #432 sera fusionnée | ⏳ ouverte |

Aucune version d'omarchy publiée ne contient encore ces correctifs : la dernière est v0.4.4, du 5/11 à 00 h 16. #132 reste ouvert pour #375 et #430 : le mainteneur a dit qu'il reporterait #430 dans le fork une fois fusionnée, et déciderait pour #375 (report dans le fork ou attente de la prochaine version).

### xtool (xtool-org/xtool)

| Ticket | PR | Sujet | État |
|---|---|---|---|
| #425 | #427 | Profil de développement : tous les appareils (pagination) | fermée par le mainteneur, reprise dans **#430** |
| #426 | #428 | 409 « Multiple profiles found » | fermée par le mainteneur, reprise dans **#430** |
| #425, #426 | **#430** (kabiroberai) | « ds: fix profile creation conflicts » : pagination, appareils désactivés exclus, vérification d'annulation, suppression du profil `XTL profile <id>` de ce bundle après la lecture des pages | ✅ fusionnée le 6/11 à 05 h 15 (`ac40282`), dans aucune version publiée |
| (amont) | #375 | Arrêt sur une entrée standard qui n'est pas un tube | ✅ fusionnée le 28/10, mais dans **aucune version publiée** (après 1.24.0) |
| **#431** (le nôtre) | | La compilation release plante le compilateur sous Linux depuis #389 (RCodesign), bissecté, reproduit dans leur image ; cause : bug du compilateur Swift (swiftlang/swift#94055, CoroSplit), déclenché par deux `unimplemented()` | ⏳ ouvert (6/11) |
| #431 | **#432** (la nôtre, brouillon niveau 2) | Contournement : `reportIssue` + `throw UnimplementedFailure` dans `UnimplementedSigner` | ✅ approuvée par le mainteneur (6/11), relue, niveau 1, pas encore fusionnée |

Le mainteneur a fermé #427 et #428 le 5/11 pour reprendre leur contenu dans #430, qui contient tous nos points
sauf la tolérance d'un 404 à la suppression (deux installations simultanées du même bundle), un point mineur.
Il n'y a plus de rebase à faire de notre côté. Le 6/11 : main d'xtool ne compile plus en release depuis #389 (ticket #431), d'où le pin sur `03fb48c` dans #138. Testé ce jour : `xtool install` avec `/dev/null` en entrée sur l'iPhone 11 Pro, et les deux apps. Sur l'iPhone 14 de Laureline, `xtool install` reste bloqué à « Installing 100% » (déjà vu la veille, propre à ce téléphone). `ac40282` s'applique sans conflit sur le pin `a8a5a40` (vérifié le 6/11 par `cherry-pick -x`), comme `4ec0e96` (#422, plantage du formateur de date d'anisette), fusionnée juste après.

Tests réels faits :
- équipe Apple de 48 appareils ;
- iPhone 14 (iOS 27.2) en 28ᵉ position ;
- bundle avec deux profils ;
- résultat : profil recréé avec 49 appareils, l'autre profil gardé, app installée et lancée ;
- xtool 1.24.0 plus les correctifs du fork : Aero et l'app KMP construites, signées, installées et lancées.

Branches : forks `c4software/omarchy-apple-dev` et `c4software/xtool` ; clones dans `~/projets/c4software/`.

## 2. Ce que dev-box peut retirer, et quand

| Contournement dans dev-box | Fichier | Remplacé par | Retirable quand |
|---|---|---|---|
| `with_configuration` (monkeypatch de `Generator.config_layers`) et `cmd_convert` | `lib/ios-xcode.py` | `xcodeproj2xtool.py --configuration <nom>` (#125) | omarchy > v0.4.4 publiée |
| `cmd_symbols`, `cmd_catalogs`, `DevboxAssetSymbolExtensions.swift`, option `--no-asset-extensions` | `lib/ios-xcode.py`, `lib/ios-xcode.sh` (fin de `ios_xcode_project`) | le convertisseur écrit `GeneratedAssetSymbolExtensions.swift` (#127) | idem |
| Fusion de l'Info.plist de l'app dans `<produit>_<produit>.bundle/Info.plist` | `lib/ios-common.sh`, `ios_ship_build` (bloc python) | `ship.sh --device` étape 4 (#129) | idem |
| `cmd_darwin_manifests`, `cmd_patch_manifests`, copies dans `build/devbox-ios/deps/`, option `--no-darwin-manifests` | `lib/ios-xcode.py`, `lib/ios-xcode.sh` | `tools/host-manifests.py <paquet>` (#131), copies dans `<paquet>/.host-manifests/` | idem |
| Lien du framework KMP : `ios_kmp_distribution`, `ios_kmp_data`, `ios_kmp_link`, `ios-kmp.init.gradle`, `cmd_xcframework` | `lib/ios-kmp.sh`, `lib/ios-kmp.init.gradle`, `lib/ios-xcode.py` | `kmp/build-framework.sh <racine> --module :x --dynamic --xcframework` (#134) | idem |
| `ios_piped` (xtool lancé avec un tube en entrée) | `lib/ios-common.sh`, tous les appels à xtool | xtool #375 | quand omarchy publiera une version après v0.4.4 (main contient #375 via #139) |
| Signature par `provision-dev.py` / `sign-dev.sh` au lieu de `xtool install` | `lib/ios-common.sh`, `ios_install` | xtool #427 et #428 | facultatif : garder, car ce sont des outils d'omarchy qui marchent ; à revoir seulement si on veut revenir à `xtool install` |

À garder, ce n'est pas un contournement d'un manque en amont :
- `ios_root_env` (Docker rootless : root avec les outils de l'utilisateur de la box) ;
- `ios_device` (relance d'usbmuxd, `timeout 15` sur `xtool devices`) ;
- `ios_stop`, `ios_launch`, `ios_logs` ;
- XcodeGen (`ios_xcode_xcodegen`, génération sur place) ;
- `--package name=path[@ref]` (dépôt privé sans clé SSH dans la box) ;
- `--signed-suffix` ;
- `cmd_binary_target` (le README KMP d'omarchy demande de déclarer le `binaryTarget` à la main) ;
- `--min-ios 17` (symboles d'assets générés sous Linux, iOS 17 seulement).

Pistes à proposer plus tard en amont (facultatif) : la déclaration du `binaryTarget` KMP, la génération
XcodeGen et l'option `--package` dans le convertisseur.

## Branche `omarchy-next` (préparée le 5/11/2026)

Les contournements de la section 2 marqués « omarchy > v0.4.4 » sont retirés dans la branche `omarchy-next`
de dev-box, qui n'est pas fusionnée. Elle appelle les outils d'omarchy :
- `xcodeproj2xtool.py --configuration`, avec ses raccourcis d'assets ;
- `host-manifests.py` ;
- `kmp/build-framework.sh --xcframework` ;
- la fusion du plist par `ship.sh`.

Elle ajoute aussi la vérification de la version du clone (`need_oad_ref`, et une ligne `omarchy` dans
`devbox ios status`), et la doc est à jour.

Le 6/11, sans attendre une version publiée d'omarchy :
- `OAD_TAG` devient `OAD_REF`, qui accepte un tag ou le SHA complet d'un commit. Les tags sont récupérés
  comme tags, les commits par leur SHA (GitHub les sert même sans branche ni tag dessus).
- `OAD_REF` est épinglé sur `031155f` (main d'omarchy après #139, avec #125, #127, #129, #131, #134 et le pin
  xtool `c9f4363` qui contient #375).
- `ios_piped` est retiré : xtool ne s'arrête plus sur une entrée qui n'est pas un tube.
- À la prochaine version publiée d'omarchy, on pourra remettre un tag dans `OAD_REF`.

Testée le 5/11 dans un conteneur jetable :
- l'image de la branche, sur une copie reflink du home ;
- le clone d'omarchy à `main` (`88d3a3c`), tagué `v0.4.5` en local ;
- les deux apps construites de bout en bout par leurs scripts (`DEVBOX_CONTAINER=…`), installées et lancées
  sur l'iPhone de Laureline : Aero via `.host-manifests/RxSwift` et `GeneratedAssetSymbolExtensions.swift`
  du convertisseur, l'app KMP via `kmp/build-framework.sh` ;
- le garde-fou de version vérifié (épinglé `v9.9.9` : arrêt avec le message `devbox dev-env ios`).

Avertissement SwiftPM « Conflicting identity for rxswift » (RxBluetoothKit, via aspool-library) : il était
déjà là avec `deps/`, ce n'est pas bloquant.

## 3. À faire après la publication

### A. Nouvelle version d'omarchy (v0.4.5 ou plus, avec #125, #127, #129, #131, #134, et #135 si fusionnée)

Avec la branche `omarchy-next`, le travail se réduit à :
1. ~~mettre le vrai tag dans `OAD_TAG`~~ : fait le 6/11 avec `OAD_REF` sur le commit `031155f` ;
2. rebaser sur `main`, construire, retester les deux apps (conteneur jetable, comme ci-dessus) ;
3. fusionner, taguer et pousser ;
4. retirer l'exemple `--no-asset-extensions` de l'en-tête de `devbox-build.sh` d'application-ios
   (l'option arrête maintenant la commande) ;
5. une fois dans la box : `devbox dev-env ios`, puis supprimer `~/.cache/devbox-ios-kmp` (chez dev et chez
   root).

Le détail des retraits, pour mémoire :

1. Dans `rootfs/usr/share/devbox/dev-envs/ios.sh`, passer `OAD_TAG` à la nouvelle version, après avoir lu
   son CHANGELOG.
   - Si #135 en fait partie, xtool est reconstruit par `install-toolchain.sh` (environ 7 min).
   - Le SDK n'est pas à refaire : l'empreinte reste `epoch=4`.
   - Vérifier `XTOOL_SDK_VERSION` dans leur `install-toolchain.sh`.
   - Point à régler en même temps : le clone d'omarchy vit dans le home de la box (volume persistant), et
     il ne change de tag qu'avec `devbox dev-env ios`. Une nouvelle image n'y touche pas. `need_ios`
     (`dev-box-ios`) ne vérifie que sa présence. Il faut faire vérifier par `devbox ios xcode` / `kmp` que le
     clone est bien à `OAD_TAG`, et sinon arrêter avec le message « devbox dev-env ios » (ou le mettre à
     jour lui-même). Sans ça, le nouveau code appellerait `host-manifests.py` ou `kmp/build-framework.sh`
     absents de l'ancien clone.
2. Retirer les contournements de la section 2, marqués « omarchy > v0.4.4 » :
   - `lib/ios-xcode.sh`, étape project :
     - `convert` remplacé par `xcodeproj2xtool.py ... --configuration "$IOS_XCODE_CONFIGURATION"` ;
     - plus de `symbols` / `catalogs` ;
     - `darwin-manifests` / `patch-manifests` remplacés par `host-manifests.py "$pkg"` ;
     - attention : `host-manifests.py` fait lui-même `swift package resolve` (deux fois s'il remplace
       quelque chose) et refuse les manifestes qu'il ne sait pas lire. Garder une option pour le désactiver,
       ou retirer `--no-darwin-manifests`.
   - `lib/ios-common.sh` : retirer le bloc python de fusion du plist dans `ios_ship_build`.
   - `lib/ios-kmp.sh` : appeler `$OAD_DIR/kmp/build-framework.sh` (`--dynamic --xcframework --out`), puis
     supprimer `ios-kmp.init.gradle` et la partie link. Garder l'interface `devbox ios kmp`, si elle reste
     utile, comme simple appel à leur script.
     - Cache : leur script utilise `~/.cache/omarchy-apple-dev/kmp`, qui remplace
       `~/.cache/devbox-ios-kmp` (1,4 Go chez root et 1,4 Go chez dev dans la box, à supprimer ensuite).
   - `lib/ios-xcode.py` : supprimer `with_configuration`, `cmd_symbols`, `cmd_catalogs`,
     `cmd_darwin_manifests`, `cmd_patch_manifests`, `cmd_xcframework`, et leurs aides (`words`,
     `swift_name`, `provides_namespace`, `collect`, `host_test_lines`).
   - Options à retirer, ou à garder comme alias sans effet : `--no-asset-extensions`,
     `--no-darwin-manifests`.
3. Changement de comportement à documenter : le convertisseur d'omarchy refuse un asset dont il ne sait pas
   calculer le nom de symbole, et la conversion s'arrête :
   - nom qui commence par une marque combinante ;
   - caractère de formatage (U+200D, etc.) ;
   - point de code inconnu de Python ;
   - nom réduit à `_`.

   Les mots réservés (`default`, `self`, etc.) sont écrits entre backticks.
4. Revalider en réel, iPhone branché et déverrouillé :
   - `~/projets/aspool/application-ios/devbox-build.sh` (Aero : RxSwift, SwiftGen, assets, réglages) ;
   - `~/projets/aspool/application-android/iosApp/devbox-build.sh` (KMP : framework, ressources Compose) ;
   - vérifier l'icône, les images de l'accueil et des consignes, l'écran Réglages (SwiftGen), le
     lancement et la relance.
5. Documentation :
   - dev-box : `docs/dev-envs.md` (section iOS, l. 220-235 environ), `docs/commands.md`,
     `rootfs/usr/share/devbox/help/ios.txt` (puis `help_check`), `--help` de `ios-xcode.sh` ;
   - en-tête de `devbox-build.sh` d'application-ios : l'exemple `./devbox-build.sh run --no-asset-extensions`
     de la ligne 24 est à retirer si l'option disparaît.
6. Tag dev-box (v1.55 ou plus), push, puis vérifier que les deux scripts des apps recréent bien le conteneur
   sur la nouvelle image.
7. Côté apps (application-ios, application-android/iosApp) : rien à changer dans les scripts.
   - Ils n'utilisent que `--target`, `--kmp`, `--configuration`, `--package` et `--signed-suffix`, qui
     restent.
   - Ils tirent l'image `:latest` et recréent le conteneur d'eux-mêmes.
   - Une fois après la mise à jour : `devbox dev-env ios` dans la box, sauf si l'étape 1 le fait seule (xtool
     reconstruit, environ 7 min si le pin change), et « Faire confiance » à refaire sur l'iPhone, puisque le
     conteneur est recréé.
   - Seule retouche : l'exemple `--no-asset-extensions` de l'en-tête d'application-ios, si l'option
     disparaît.

### B. Fusion de xtool #430 (qui remplace #427 / #428)

1. Proposer chez omarchy le cherry-pick de #430 sur la branche xtool du fork
   (`omarchy/1.24.0-fixes`, ou celle qui existera après joshuaswarren/xtool#3), et le pin qui va avec.
2. Rien à retirer dans dev-box : la signature passe par `provision-dev.py`. Facultatif : revenir à
   `xtool install`.

### C. Version d'xtool qui contient #375

1. Proposer chez omarchy le pin sur cette version, avec les correctifs du fork rejoués comme pour #135.
2. Une fois cette version d'omarchy publiée et épinglée dans dev-box, retirer `ios_piped` de
   `lib/ios-common.sh`. Le garder pour `xtool devices` si besoin, puisque `timeout` reste utile.
3. Retester une installation complète.

### D. Ménage, une fois tout fusionné

- Supprimer les branches des forks : `c4software/omarchy-apple-dev` (`xcodeproj2xtool-configuration`,
  `asset-symbol-extensions`, `ship-bundle-info-plist`, `host-manifests`, `kmp-framework`, `xtool-1.24.0`) et
  `c4software/xtool` (`fetch-profile-all-devices`, `fetch-profile-replace-own`, `oad-1.24.0`).
- `~/projets/c4software/xtool/.build` : 3 Go, sur l'hôte, à supprimer quand plus aucune PR xtool n'est
  ouverte.
- Dans la box : `~/.local/lib/omarchy-apple-dev/xtool-f0a1f90…` et `~/.cache/omarchy-apple-dev/xtool-f0a1f90…`
  (ancien pin d'omarchy, avant v0.4.4 : environ 2 Go, inutilisés).
- Apple (équipe 466E4Z68W9) : profils `omarchy-apple-dev development XTL-69A6DE8C.fr.aspool.aero.staging`
  (et `.kmp`), créés par dev-box. À garder tant qu'on installe depuis la box.
- iPhone de Laureline (iPhone 14) : Aero staging et l'app KMP y ont été installées pour les tests. À
  supprimer si elles ne doivent pas rester.
