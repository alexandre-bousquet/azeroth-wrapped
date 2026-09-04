# Azeroth Wrapped

**Azeroth Wrapped** transforme votre activité dans World of Warcraft en récapitulatif visuel hebdomadaire, mensuel, saisonnier ou annuel.

La version `1.1.0` cible Retail et l’interface `12.0.7` (`120007`). Elle ne dépend d’aucune bibliothèque externe et n’analyse aucune valeur de combat sensible.

## Fonctionnalités du MVP

- temps en ligne, temps actif et temps AFK ;
- nombre de sessions et plus longue session ;
- temps par personnage et zone ;
- activité dominante : monde ouvert, ville, donjon, raid, scénario/gouffre, champ de bataille ou arène ;
- morts et lieu le plus meurtrier ;
- compagnon de groupe le plus fréquent, mesuré au temps passé ensemble ;
- PNJ rencontrés lors d’interactions ;
- évolution nette des golds, gains, dépenses et solde connu sur les personnages suivis ;
- boss de donjons et de raids vaincus, avec répartition et boss le plus souvent terrassé ;
- vues semaine, mois, saison, année et depuis l’installation ;
- mode aperçu immédiat sans fausses données persistantes ;
- huit cartes cliquables donnant accès aux classements et détails de la période sélectionnée ;
- filtre global permettant de sélectionner un ou plusieurs personnages ;
- calendrier d’activité quotidien avec intensité du temps actif et activités terminées ;
- mode de capture propre pour partager les cartes.

Toutes les données restent dans les `SavedVariables` de World of Warcraft. La collecte commence à l’installation : l’addon ne peut pas reconstruire l’historique antérieur.

## Installation

1. Copier le dossier `AzerothWrapped` dans `_retail_/Interface/AddOns/`.
2. Vérifier que le fichier se trouve exactement à l’emplacement `AzerothWrapped/AzerothWrapped.toc`.
3. Activer l’addon à l’écran de sélection des personnages.
4. En jeu, saisir `/aw`.

### Installation de développement

Le projet peut être placé dans un dossier `AzerothWrappedDev`. World of Warcraft chargera alors `AzerothWrappedDev.toc`, affichera clairement la variante **Dev** et utilisera `AzerothWrappedDevDB` afin de ne pas mélanger ses données avec la version CurseForge. Ne pas activer les deux variantes en même temps.

## Options en jeu

Une page **Azeroth Wrapped** est disponible dans **Échap → Options → AddOns**. Elle permet de choisir la langue de l’addon, la période sélectionnée par défaut, les personnages inclus dans les statistiques, les cartes affichées et leur ordre, ainsi que la période de données à réinitialiser après confirmation.

## Commandes

| Commande | Action |
|---|---|
| `/aw` | Ouvre ou ferme le récapitulatif |
| `/aw preview` | Affiche une démonstration sans modifier les statistiques |
| `/aw week`, `/aw month`, `/aw season`, `/aw year`, `/aw all` | Ouvre une période précise |
| `/aw privacy` | Masque ou affiche les noms des autres joueurs sur les cartes |
| `/aw tracking` | Met la collecte en pause ou la réactive |
| `/aw status` | Affiche l’état et le nombre de jours collectés |
| `/aw reset` | Efface tout l’historique après confirmation, sans modifier les options |

Les alias français `semaine`, `mois`, `saison`, `année`, `tout`, `confidentialité`, `collecte` et `statut` sont également acceptés.

## Architecture

```text
AzerothWrapped/
├── AzerothWrapped.toc
├── AzerothWrappedDev.toc
├── Core/
│   ├── Bootstrap.lua
│   ├── Commands.lua
│   ├── Database.lua
│   ├── Periods.lua
│   ├── Summary.lua
│   └── Util.lua
├── Localization/
│   ├── Locale.lua
│   ├── enUS.lua
│   └── frFR.lua
├── Trackers/
│   └── Tracker.lua
└── UI/
    ├── DetailPanel.lua
    ├── MainFrame.lua
    ├── Options.lua
    └── Theme.lua
```

Le stockage est organisé en agrégats journaliers. Cette structure permet de recalculer plusieurs périodes sans dupliquer les données et limite la croissance du fichier. La rétention détaillée par défaut est de 730 jours.

## Limites actuelles

- La « saison » débute au premier lancement observé pour l’identifiant de saison courant ; l’addon ne connaît pas le temps joué avant son installation.
- Les scénarios et les gouffres partagent actuellement la même catégorie lorsque le client les expose comme une instance de type `scenario`.
- Le nombre de « moments en groupe » correspond à des échantillons internes ; le temps passé ensemble est la métrique destinée à l’utilisateur.
- Les interactions avec un même PNJ dans un intervalle de cinq secondes sont fusionnées pour éviter les doublons d’événements d’interface.
- L’évolution des golds débute au premier instantané de chaque personnage. Le solde de la banque de bataillon est inclus afin que ses dépôts et retraits ne soient pas comptés comme des gains ou des dépenses. Les transferts entre vos personnages s’annulent seulement lorsque les deux portefeuilles sont observés pendant la période choisie.
- Seuls les boss pour lesquels le client confirme une rencontre terminée avec succès sont comptés ; les wipes et les boss antérieurs à l’installation ne le sont pas.
- Pour les journées historiques où plusieurs personnages ont été joués, certaines statistiques anciennes ne peuvent pas être attribuées à un personnage précis. Elles restent visibles dans la vue « Tous les personnages », sans être inventées dans les vues filtrées.
