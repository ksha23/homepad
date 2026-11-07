# HomePadKitchen

Recipes, a weekly meal plan that fills Groceries, cooking mode, kitchen timers and wake-up alarms for HomePad. This is HomeView's kitchen story, built to work with any recipe site and any AI provider, and the Alarms app that HomeView ships for the nightstand. Alarms live here beside timers, as they share the Clock app on iPad, and they use the same AlarmKit permission, chimes and background setting.

## Features

**Timers** (`services.timers`)
- `KitchenTimerService` replaces Core's in-memory service. Timers are named, run side by side, pause, resume and take +1 minute.
- State is saved as JSON in Application Support. Running timers store their end date, so time keeps passing while HomePad is closed. A timer that ended while the app was closed rings on the next launch. Timers that ended more than an hour earlier are dropped.
- Finishing posts `.timerFinished(id:label:)`.
- AlarmKit rings timers while HomePad is in the background or the iPad is locked. Each running timer gets a fixed-date alarm one second after it ends. In the foreground the service sees the end first, cancels the alarm and the in-app overlay rings instead. If someone stops the system alarm on the Lock Screen, the overlay does not ring again. Permission is requested the first time a timer starts.
- One Live Activity (ActivityKit) shows every active timer on the Lock Screen and in the iPhone companion's Dynamic Island. The same state is written to the App Group for the Home Screen widget.

**Timer finished overlay**: full screen, opaque and dark in every appearance, a glowing tick ring, Stop and +1 min, Stop All when several are done. The ring breathes while someone may be watching and holds still when the display dims or motion is off. A raised palm (`.gesture(.openPalm)`) stops every ringing timer, like Stop. The chime loops on a `.playback` claim on `services.audioSession` and stops itself after ten minutes. It posts `.wake` so the display leaves sleep.

**Timers app** (`timers`): a large ring countdown (HomeView's tick ring), the list of timers, preset buttons and hour, minute and second wheels for a new timer. It reopens on the timer it was showing, or the most urgent one once that timer is gone.

**Reopening where you left off** (`KitchenAppState`, shared by the household)
- Timers: the timer in the big ring (`timers.selected`).
- Recipes: `KitchenContext` outlives the app's view, so within a launch the app reopens on the same library search, card or cooking step, with the same servings, units and ticked ingredients. After a relaunch it reopens the recipe that was open (`recipes.open`), and cooking mode on its step (`recipes.cookingStep`) while that is recent: within four hours on the same day, like Calendar's date. Otherwise the recipe opens on its card.
- Meal plan: the plan reopens when it was open, or when the recipe open came from it, so Back goes to the plan again (`recipes.mealPlanOpen`). The week it showed comes back while recent (`recipes.mealPlanWeek`, a time position), else this week.
- Anything that opens a recipe first wins: the assistant, an import, a share from the iPhone and `-KitchenDemo`. Not restored: the preview sheet and the ingredients sheet. From across the room only the ring shows. Each second rolls in, down while it counts and up for +1 min, and the pause button turns into play in place. Countdowns tick only while they are on screen and running, so thumbnails and a sleeping display cost nothing.

**Alarms app** (`alarms`)
- Alarms are personal. Each belongs to the household member who set it, and the app is a personal app (`requiresRecognizedMember`), so the shell's recognition gate and Home Screen rules apply as for Find My. A guest or someone picked by hand without recognition cannot see, change or turn off another person's alarms. With nobody in People yet, the gate asks to add someone first.
- A list like the Clock app's Alarms: each alarm's time in big light numerals with AM or PM, its label and days under it, and a switch. Off alarms are dimmed. Above the list, "Next alarm tomorrow at 6:30 AM, in 9 hr 14 min", redrawn once a minute. Add Alarm is the header's prominent action.
- Tapping an alarm opens the editor (`SheetScreen`, page-sized): hour and minute wheels, a round button per day to repeat (in the locale's week order, "Weekdays" or "Once" under them), a label and Snooze. Add or Save is the one action, and Delete Alarm sits at the bottom for an alarm being changed. Saving turns the alarm on.
- `AlarmService` keeps the alarms and each one's next ring in Application Support (`alarms.json`). A repeating alarm rings on its days, and a one-time alarm turns off after it rings. When a person leaves the household, their alarms are removed within a minute.
- At its time an alarm rings in the app, full screen and dark over everything (`AlarmRingingOverlay`): the time, whose alarm and its label, Snooze (nine minutes, when allowed) and Stop, and bells on a loop on their own audio claim, so a timer and an alarm never silence each other. It rings for everyone in the room, so anyone may snooze or stop it. It posts `.wake`, turns red at night, and stops by itself after ten minutes.
- AlarmKit rings each alarm while HomePad is in the background or the iPad is locked, with a Snooze button that counts down nine minutes. Each alarm has one system alarm, set for its next ring one second late. In the foreground the service rings first and cancels it, as timers do, and an alarm stopped on the Lock Screen does not ring again in the app. One that came due while HomePad was closed rings on the next launch if it is less than ten minutes late.
- Widget `kitchen.nextAlarm` (personal, small and medium): the recognized person's next alarm, or their next few, on the Home Screen or a face. A tap opens Alarms.

**Recipes app** (`recipes`)
- A library saved as JSON in Application Support. Two sample recipes are bundled, and the first launch adds ten everyday recipes from TheMealDB in the background (`RecipeStarterSet`): two pastas, salmon, shakshuka, pancakes, soup, noodles, burgers, a stew and lasagne. An offline first launch tries again the next time Recipes opens. The set is added once, and a recipe someone deleted is remembered (`library-state.json`) so nothing automatic brings it back. Saving it again on purpose does.
- One field, like Safari's: words search TheMealDB as they are typed (after a short pause, three letters or more), and a link imports that page. The system Paste button (no clipboard prompt) imports a pasted link or recipe text. Other modules hand recipes over with an event (see below).
- Search results replace the library until the field is cleared: saved recipes that match first, then TheMealDB's results as tiles with the photo, title, source and time. Searching, no results, offline and an unavailable service each have a calm state with Try Again.
- Tapping a result opens a preview sheet (photo, facts, ingredients, steps, a link to its TheMealDB page) with Save to My Recipes in its header. Once saved, the header button opens the library copy. The tile's context menu saves without the preview.
- A Discover shelf over My Recipes fills itself with ten random picks from TheMealDB, kept for six hours. Picks already saved are left out, and the More Ideas tile at the end swaps them. While it loads it shows placeholders, and offline it says so in one line with Try Again. Nothing waits on the network.
- Every way in ends in `KitchenContext.save`: a link, scanned text, a search result, a Discover pick and the assistant. Saving the same page again replaces the earlier copy and keeps its pin and photo.
- Parsing: schema.org JSON-LD first. It handles `@graph`, top-level arrays, `mainEntity` nesting, `@type` arrays and IRIs, `@id` references, HowToSection, HowToStep, HowToDirection, ItemList, nested arrays, HTML in step text, ISO 8601 and plain-text durations, every `recipeYield` shape, and image strings, arrays and ImageObjects (the largest wins). Broken JSON is repaired (raw newlines, comment wrappers, trailing semicolons, encoded quotes). Microdata comes next, then pages with "Ingredients" and "Instructions" headings.
- Import scanned or pasted text. With an AI provider configured, a strict JSON prompt structures it as a self-contained text task (`AssistantRequest.textTask`): the provider gets the prompt and the text only, with no tools, no chat history and nothing about the household. Otherwise, or if the reply is unusable, heuristics read it.
- The recipe card follows HomeView: a full-bleed photo, title, source, time and servings, and Ingredients and Start Cooking buttons that span the card, as tall as a round control, so they read from the stove. Its text and glass stay light on the photo's dark gradient in every appearance. The menu offers Share (system share sheet), Choose Photo (system Photos picker), Pin and Open Original Page.

**Cooking mode**
- One step at a time in huge type, with step dots and next and previous buttons. The text grows when the camera sees the cook across the room, and while nobody is in view.
- Ingredient amounts are orange. Times in the text ("3 to 5 minutes", "1 hour 20 min") are tappable and also show as big timer chips that start labeled timers ("Step 2 · Butternut Squash Soup"). A chip whose timer runs shows its countdown.
- Running timers show as pills in the header and open full size. The shell's own timer pill steps aside here (`.showsRunningTimers()`).
- A dimmed preview of the next step.
- Besides the buttons, a horizontal swipe on the screen (left for next, right for previous), a tap on the next step's preview, the step dots and the assistant tools move between steps. Hand gestures do not change steps.
- The ingredient checklist scales servings, converts between as written, US and metric, and adds unticked items to the Groceries list with the Add to Groceries button in its header (`KitchenContext.addToGroceries`, over `services.calendar.addReminder(title:due:listName: "Groceries")`).

**Meal plan** (in Recipes, `MealPlan/`)
- The Meal Plan button in the library's header opens the week: a column per day in landscape and a row per day in portrait, each with its planned recipes (photo, title, the servings it is planned for) and an Add button. Today's day is tinted in the app's color, and days gone by have a quieter label. Previous, This Week and next move between weeks, starting on the locale's first weekday.
- Add opens My Recipes as a sheet with a search field, so saved, imported and scanned recipes all plan the same way. A recipe's card also has Add to Meal Plan in its More menu, for the next seven days, at the servings chosen on the card. A planned recipe starts at the Default Servings setting, else its own servings. A recipe that does not say how many it serves (TheMealDB's) is planned and shopped for as written.
- A tap on a planned meal opens its card at the planned servings, with Back to the plan. Its menu, like a library tile's, changes the servings, moves it to another day of the week or takes it off the plan. Deleting a recipe from the library takes it off the plan too.
- Groceries, the header's one prominent action, opens the week's shopping list: every planned recipe from today to the end of the week shown (a week ahead from its first day, a week gone by not at all), scaled to each meal's servings and merged, with the recipes that need each item under it. As in the Ingredients panel, a tap marks what is already in the kitchen, and "Add 14 to Groceries" adds the rest in one go. Items whose name is still open on the Groceries list are set apart under Already on Groceries and never added twice. Checked-off items do not count.
- Merging (`GroceryMerger`): each line is scaled with `RecipeScaler` and its name cleaned (`GroceryName`): words in parentheses, notes after a comma, "to taste" or "for serving", sizes ("large") and preparation ("chopped", "minced") are left out, and the last word is made singular for matching. Packaged goods keep their preparation, since diced tomatoes in a can are a product. Lines with the same name add up: volumes with volumes and weights with weights through `CookingUnit.baseValue`, counts of the same unit and package size ("1 (15 oz) can" and "2 (15 oz) cans" make "3 (15 oz) cans"), and bare counts. When every recipe used the same unit the total stays in it. Otherwise it takes the friendliest unit (`UnitConverter.bestUnit`) of one system, or of the Units setting when the recipes mix US and metric. Volume and weight of one thing cannot be added without its density, so they stand side by side ("2 cups and 200 g flour"). Counts of things bought whole round up (no half onions or half cans), and the name goes plural for a count above one. Headings ("For the sauce:") and tap water are left out. With the Units setting on US or metric, every amount is converted first.
- Example: Roasted squash soup planned for 8 (written for 4) and chili for 6. "2 tablespoons olive oil" doubles to 4 tablespoons and the chili's "1/4 cup olive oil" is 4 more, so the list says "½ cup olive oil". "1 medium yellow onion, chopped" doubled and "2 yellow onions, diced" make "4 yellow onions". "2 cloves garlic, minced" doubled and "3 garlic cloves" make "7 cloves garlic". "2 cups water" is left out.
- The plan is saved per household on this iPad as `meal-plan.json` beside the recipe library in Application Support (`MealPlanStore`), like the recipes it points to. Each planned meal keeps its day as a year, month and day, so it stays on its day if the time zone changes.
- Widget `kitchen.mealPlan` (small and medium): today's meals, or tomorrow's once today has none, and on the medium size today and tomorrow side by side, as many as fit with the rest counted. It moves on at midnight. A tap opens the plan.
- Assistant tools (`MealPlanTools`), none needing recognition since the plan is the household's:
  - `get_meal_plan(day, days)` ("what's for dinner Thursday"). The plan has no breakfast, lunch or dinner, so the answer is the day's recipes.
  - `plan_meal(recipe, day, servings)` ("put chili on Friday") plans a saved recipe and shows the plan. A recipe not saved yet gets the hint to use `search_recipes` and `save_recipe` first.
  - `remove_planned_meal(day, recipe)` ("take the chili off Friday"), or every meal on the day when no recipe is named.
  - `add_meal_plan_to_groceries(day)` ("add this week's meals to the shopping list") does what the Groceries sheet does for the week of that day, and says what was already on the list.
  - Days are ISO 8601 dates, today, tomorrow or weekday names, which mean the next one from today on ("next Friday" said on a Friday is a week out).
- While the plan is on screen, the assistant hears the week's meals (`RecipeScreenContext`), so "add these to my list" needs no dates.

**Registry contributions**
- Apps `timers`, `recipes` and `alarms` (personal).
- Widgets: `kitchen.timers` (running timers, opens Timers), `kitchen.recipeOfTheDay` (changes at midnight), `kitchen.mealPlan` (today's and tomorrow's meals, opens the plan) and `kitchen.nextAlarm` (personal, opens Alarms).
- Control Center tile `kitchen.quickTimers` with four quick timers.
- Settings pane `kitchen`.
- Overlays `kitchen.timerFinished` and `kitchen.alarmRinging`.
- Assistant tools: `open_recipe`, `cooking_next_step`, `cooking_previous_step`, `read_current_step`, `read_ingredients`, `scale_recipe`, and the meal plan's four (above). The generic timer tools belong to the assistant module.
- Assistant tools for alarms (`AlarmTools`), each needing a recognized member and acting on their alarms only:
  - `set_alarm(hour, minute, label, repeat)` ("set an alarm for 7"). A time without AM or PM means the morning. The same time and days already set turns that alarm on instead of adding a second. The reply says when it rings.
  - `turn_off_alarms(hour, minute, label)` ("turn off my alarms"): all of the person's alarms, or those that match. While one of theirs rings it stops it instead, so it still rings next time.
  - `list_alarms` ("what alarms do I have").
- The Recipes app tells the assistant what it shows (`RecipeScreenContext`): the recipe card, or the step in cooking mode, with the ingredients as they read on screen (scaled to the chosen servings, and which are ticked off as on hand), or the catalog recipe being previewed. "Add these ingredients to my shopping list" and "how long does this bake" then need no recipe name.
- Assistant tools for new recipes (`RecipeCatalogTools`):
  - `search_recipes(query)` searches TheMealDB, shows the results in the Recipes app and returns them numbered ("find a chicken curry recipe"). Cooking mode is never interrupted.
  - `preview_recipe(number or name)` opens one result's preview and returns its ingredients and steps to read.
  - `save_recipe(number or name)` saves a result, or the one being previewed ("save that one"), and opens it. Its description tells the model to save only after the person picks one or agrees, and an unclear choice gets a question back instead of a guess. Saving is not a sensitive action, so the assistant asks no confirmation prompt of its own.
  - `import_recipe_link(url)` imports a page ("add the recipe from this link").

**Recipe source: TheMealDB** (`Recipes/Catalog/`)
- `RecipeCatalog` is the contract (search, one recipe, Discover picks, recognizing the catalog's own links). `MealDBCatalog` implements it with plain `URLSession`, and `MealDBRecipeMapper` turns a record into a `Recipe`.
- No key is needed: TheMealDB's public key "1" is for development and personal use, which a household's own HomePad is. Their terms allow storing what the API returns as long as TheMealDB is credited, so every saved recipe has the source "TheMealDB" and links to its TheMealDB page. The original site, when TheMealDB names one, is kept in the summary ("Adapted from bbcgoodfood.com.").
- An optional supporter key from TheMealDB goes in Settings > Kitchen > Recipe Search and lives in the keychain (`KitchenSecrets.mealDBKey`). It brings ten random picks per request for Discover instead of one.
- Name search wants the words in order, so "curry chicken" falls back to searching each word and ranking recipes by how many of the words their title, kind, tags and ingredients contain.
- Links to themealdb.com pages import through the API, since TheMealDB asks apps not to scrape its pages.
- TheMealDB has no time or servings fields. A "Prep: 15min › Cook: 30min" line in the method is read when there is one. Otherwise the time shown is the sum of the times the steps state, a lower bound, and nothing under ten minutes. Servings stay empty, so these recipes cannot be scaled.
- Instructions arrive as lines, paragraphs, "STEP 1" headings or "01." numbering. Headings and numbers are removed. Each ingredient line puts the amount first ("4 chicken breast, pounded to 1cm thickness") so scaling and conversion read it.

**Widget extension** (`Extensions/HomePadWidgets`): the timer Live Activity (Lock Screen and Dynamic Island) and a small Home Screen widget that reads the App Group snapshot.

## Events other modules can post

| Event | Payload | Effect |
| --- | --- | --- |
| `.custom(name: "kitchen.importRecipeURL", ...)` | `.string(url)` | Imports the page, saves it and opens its card |
| `.custom(name: "kitchen.importRecipeText", ...)` | `.string(text)` | Structures scanned text, saves it and opens its card |

The names are also available as `KitchenModule.importURLEvent` and `KitchenModule.importTextEvent`.

## Structure

```
Sources/HomePadKitchen/
  KitchenModule.swift        registration, event listening
  KitchenContext.swift       shared state: library, search, Discover, open recipe, navigation, the one save path
  Parsing/                   numbers, durations, units, quantities, step text
  Scaling/                   unit conversion, scaling, fraction formatting
  Recipes/Models/            Recipe
  Recipes/Import/            JSON-LD, microdata, heuristics, HTML helpers, importer, AI structuring
  Recipes/Catalog/           RecipeCatalog contract, TheMealDB client and mapper
  Recipes/Search/            RecipeSearch (typing pause, last results) and RecipeDiscovery (Discover picks)
  Recipes/Library/           RecipeLibrary (JSON persistence, samples, deleted pages, recipe of the day), RecipeStarterSet
  Recipes/Photos/            RecipePhotoLoader: web photos through a disk cache, every photo decoded once per shown size
  Recipes/Views/             library, search and link field, card, ingredient checklist
  Recipes/Views/Catalog/     search results, result and Discover tiles, Discover shelf, preview sheet
  MealPlan/                  MealPlanStore (plan JSON), KitchenContext+MealPlan (planning, shoppable meals, merged groceries)
  MealPlan/Models/           MealDay and MealWeek, MealPlanFormat (day and week wording, spoken days)
  MealPlan/Groceries/        GroceryName (cleaning and matching names), GroceryMerger (scaling and adding up)
  MealPlan/Views/            the week, planned meal cards, the recipe picker, the week's groceries sheet
  Cooking/                   RecipeSession and cooking mode views
  Timers/Services/           timer service, persistence, AlarmKit, Live Activity sync
  Timers/Audio/              chime choices, synthesis, player
  Timers/Views/              Timers app, focus ring, rows, presets, picker, finished overlay
  Alarms/                    registration (KitchenAlarms) and debug launch
  Alarms/Models/             HomeAlarm (next ring) and AlarmFormat
  Alarms/Services/           AlarmService, persistence, AlarmKit rings
  Alarms/Views/              Alarms app, rows, editor, day picker, ringing alert, Next Alarm widget
  Widgets/  Controls/  Settings/  Tools/  Support/
  Resources/SampleRecipes.json
```

### Shared UI

Kitchen builds on HomePadUI: `TickRing`, `PageDots`, `GlassIconButton`, `GlassCapsuleButton`, `LiveTime`, `AdaptiveStack`, and `DetailHeader` for cooking mode.

### Core additions

`Packages/HomePadCore/Sources/HomePadCore/Extensions/Kitchen/TimerActivityAttributes.swift`. It holds the ActivityKit attributes shared with the widget extension and the App Group snapshot helpers. It is guarded with `canImport(ActivityKit) && os(iOS)` because `ActivityAttributes` is unavailable on macOS, where Core also builds.

## Settings (Settings > Kitchen)

Curated choices only:
- Timer sound: Chime, Bells, Kitchen Beeps or Soft Pulse (previewed when picked).
- Ranged times start at the shortest or the longest time.
- Presets: up to six lengths picked from a fixed catalog.
- Default servings: as written, or 1, 2, 3, 4, 6 or 8.
- Units: as written, US or metric.
- Ring in the background (AlarmKit), for timers and wake-up alarms, with the permission state and a button to allow it.
- Live Activities.
- Restore the sample recipes.
- Recipe Search: an optional TheMealDB supporter key, kept in the keychain.

## Dependencies

None beyond Apple frameworks (SwiftUI, AlarmKit, ActivityKit, WidgetKit, PhotosUI, AVFoundation). The JSON-LD parser is our own because it already handles the shapes real sites produce and needs no HTML DOM. TheMealDB is reached with plain `URLSession`.

## Debug launch arguments (Debug builds)

```
-HomePadOpenApp recipes -KitchenDemo card            the first recipe's card
-HomePadOpenApp recipes -KitchenDemo cooking -KitchenDemoStep 6
-HomePadOpenApp timers  -KitchenDemo timers          three timers, one paused
-KitchenDemo finished                                a timer that finishes after two seconds
-KitchenDemoNoAlarms YES                             skip the AlarmKit prompt for screenshots
-KitchenDemoTimers YES                               the three demo timers alongside any other mode,
                                                     such as cooking mode with timers running
-HomePadOpenApp alarms -KitchenDemo alarms           three alarms for the recognized demo member
                                                     (with -HomePadDemoContent YES -HomePadMember Alex -HomePadRecognized YES)
-KitchenDemo alarmRinging                            those, with the first ringing
-KitchenDemoAlarmEditor new|edit                     the New Alarm sheet, or the first alarm in the editor
-HomePadOpenApp recipes -KitchenDemo search -KitchenDemoQuery "chicken curry"
-HomePadOpenApp recipes -KitchenDemo preview         the first result's preview sheet
-HomePadOpenApp recipes -KitchenDemo saved           the first result saved, its preview showing Saved
-HomePadOpenApp recipes -KitchenDemo assistant       runs search_recipes then save_recipe like the assistant,
                                                     replies in the app's tmp/KitchenAssistantDemo.txt
-KitchenDemoCatalog offline                          TheMealDB answers as if HomePad were offline
-HomePadOpenApp recipes -KitchenDemo mealPlan        this week's plan, planned once with three demo recipes
                                                     (chili, tacos, a smoothie) and the samples, sharing ingredients
-HomePadOpenApp recipes -KitchenDemo mealPlanGroceries   the same, with the week's merged shopping list open
```

## Tests

`scripts/build-package.sh HomePadKitchen test` runs the Swift Testing suite:
- recipe pages: fixtures in the shapes of a WordPress plugin graph, a big publisher's top-level array, a newspaper-style object, a WebPage `mainEntity`, a hand-written blog with invalid JSON, nested HowTo shapes, microdata, a plain page and a page without a recipe
- durations, ISO 8601 and quantity extraction tables
- scaling, conversion and fraction formatting
- timer persistence, relaunch, stale timers and Lock Screen dismissal
- alarms: next rings for one-time and repeating alarms, ringing, stop, snooze, the ten-minute window, relaunch, Lock Screen dismissal and people who left, plus the alarm tools and spoken days
- scanned text with and without an AI provider, and the library
- TheMealDB: responses saved from the live API as fixtures (no test touches the network), instruction shapes, ingredient lines, word-by-word fallback, offline, the supporter key and its own links
- the starter set (once, skipping deleted recipes, retrying after an offline launch), Discover freshness, search phases and the one save path
- the assistant's recipe tools, called by name with JSON arguments
- the meal plan: merging across recipes scaled to their servings, rounding counts up, units that convert and ones that cannot, matching list items by name, what the Groceries list already has, saving and deleted recipes, the days worth shopping for, spoken days, and the four plan tools

## Needs real-device testing

- AlarmKit on iPadOS: the alarm rings when HomePad is in the background or locked, the foreground hand-off to the overlay, and the Lock Screen Stop path.
- Wake-up alarms the same way, plus the system Snooze button and how loud the bells are from across a bedroom.
- Live Activities on iPad and on the iPhone companion, including the Dynamic Island layout.
- Chime volume and the `.playback` claim alongside music on AirPlay speakers.
- The Home Screen widget refresh after timers change, through the App Group.
- Importing from real recipe sites over the network.
- TheMealDB search, Discover and the starter set on the iPad's own network (checked in the simulator against the live service).
- The Groceries reminder list with the real calendar service, including the meal plan's merged list and Already on Groceries against a list shared from an iPhone.
- The Meal Plan widget on the Home Screen and a face, and the plan's long-press menus at arm's length.

## Known gaps

- Ingredient names are not pluralized when scaled on a recipe's card ("2 onion"). The meal plan's merged list does make a count's name plural.
- The meal plan puts recipes on days, without breakfast, lunch or dinner slots.
- Merging matches names after cleaning them, so "kosher salt" and "salt", or "milk" and "whole milk", stay apart, and a list item matches only by the same name. Singulars come from rules, not a dictionary, which is enough to match a word with itself but can read oddly ("sage leave" as a key).
- The plan's Add to Groceries adds items as they are. An item already on the list keeps its own amount, since Reminders items cannot be renamed through `CalendarService`.
- Converting volume to weight (cups of flour to grams) needs ingredient densities and is not attempted. A parenthetical weight written by the author is used when present.
- Web photos are kept in a disk cache once they have shown, which iPadOS may clear when storage runs low. A photo that never showed needs the network.
- TheMealDB has about 800 recipes, so searches for less common dishes find nothing. The broader recipe APIs all need a key, and Spoonacular forbids keeping recipes longer than an hour.
- Times on TheMealDB recipes are the sum of the times their steps state, a lower bound. They have no servings, so they cannot be scaled.
- Each timer chip label is per step, so starting the same step's timer twice reuses the running one.
- Each alarm has one system alarm, for its next ring. If HomePad stays in the background past it, the next one is set the next time HomePad comes to the front. A snooze started on the Lock Screen is taken over by the app when it comes to the front, and rings then if the alarm is still within its ten minutes.
- A raised palm does not stop or snooze alarms, so a sleeper's wave never turns one off.
- Clock faces do not show the next alarm yet. The Next Alarm widget does, on any face with widgets.
