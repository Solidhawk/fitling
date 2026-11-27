import { Plus, Search } from "lucide-react";
import { Fragment, type ReactNode, useEffect, useMemo, useState } from "react";
import type { FitlingCore, RecipeSummary } from "../core/fitlingCore";
import { createRecipe, type Ingredient, mealSlots, type MenuRows, type OwnRecipe, recipeIngredients } from "../data/menu";
import { supabase } from "../data/supabase";
import { typingLanguage } from "../data/training";
import { decimal, kcal, parseNumber } from "../format";
import credits from "../generated/recipeCredits.json";
import { t } from "../i18n";
import { amountText, recipeDetail, recipeSteps } from "../menu/texts";
import { FormSheet } from "../ui/FormSheet";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { PickerRow } from "../ui/PickerRow";
import { initial } from "../ui/ProductRow";
import { Stepper } from "../ui/Stepper";
import { SwipeRow } from "../ui/SwipeRow";

const photoCredits = credits as Record<string, { author: string; licence: string; page: string }>;

/** The photo of a shared recipe, shipped with the app as on iOS (Assets.xcassets/Recipes). */
function photoURL(id: string): string {
  return `${import.meta.env.BASE_URL}recipes/${id}.jpg`;
}

/** The recipe's own photo, or its first letter on a track tile when it has none (RecipeThumbnail). */
export function RecipeThumbnail({ id, own, title, size = 56 }: { id: string; own: boolean; title: string; size?: number }) {
  const [failed, setFailed] = useState(false);
  const style = { width: size, height: size, borderRadius: size / 4 };
  if (!own && !failed) {
    return <img className="thumbnail" src={photoURL(id)} alt="" style={style} loading="lazy" draggable={false} onError={() => setFailed(true)} />;
  }
  return (
    <span className="thumbnail thumbnail-placeholder" aria-hidden="true" style={{ ...style, fontSize: size * 0.45 }}>
      {initial(title)}
    </span>
  );
}

/** A recipe in a list: photo, title, energy per serving and time (RecipeRow). */
export function RecipeRow({ recipe }: { recipe: RecipeSummary }) {
  return (
    <span className="recipe-row">
      <RecipeThumbnail id={recipe.id} own={recipe.own} title={recipe.title} />
      <span className="row-stack">
        <span>{recipe.title}</span>
        <span className="footnote secondary tabular">{recipeDetail(recipe.kcalPerServing, recipe.cookMinutes)}</span>
      </span>
    </span>
  );
}

/** Recipes whose title holds what was typed, ignoring case and accents (FoodDiary.searchKey). */
function useSearch(core: FitlingCore, recipes: RecipeSummary[], query: string): RecipeSummary[] {
  const keys = useMemo(() => recipes.map((recipe) => core.searchKey({ text: recipe.title }).key), [core, recipes]);
  const term = core.searchKey({ text: query }).key;
  return term === "" ? recipes : recipes.filter((_, index) => keys[index].includes(term));
}

function SearchField({ query, onChange, testID }: { query: string; onChange: (query: string) => void; testID: string }) {
  return (
    <div className="search-bar">
      <Search aria-hidden="true" size={18} strokeWidth={2.2} />
      <input
        className="search-field"
        type="search"
        aria-label={t("menu.recipes.search")}
        placeholder={t("menu.recipes.search")}
        data-testid={testID}
        value={query}
        onChange={(event) => onChange(event.target.value)}
      />
    </div>
  );
}

/** Picks another recipe for one meal (RecipePicker). */
export function RecipePicker({
  core,
  recipes,
  onPick,
  onCancel,
}: {
  core: FitlingCore;
  recipes: RecipeSummary[];
  onPick: (recipeID: string) => void;
  onCancel: () => void;
}) {
  const [query, setQuery] = useState("");
  const shown = useSearch(core, recipes, query);
  return (
    <FormSheet title={t("menu.swap")} onSave={onCancel} onCancel={onCancel}>
      <SearchField query={query} onChange={setQuery} testID="menu.picker.search" />
      <ListSection>
        {shown.map((recipe) => (
          <ListRow key={recipe.id} onClick={() => onPick(recipe.id)}>
            <span data-testid={`menu.picker.recipe.${recipe.id}`}>
              <RecipeRow recipe={recipe} />
            </span>
          </ListRow>
        ))}
      </ListSection>
    </FormSheet>
  );
}

/** All recipes, with the user's own ones to add or delete (RecipeListView). */
export function RecipeList({
  core,
  recipes,
  onBack,
  onOpen,
  onCreate,
  onDelete,
}: {
  core: FitlingCore;
  recipes: RecipeSummary[];
  onBack: () => void;
  onOpen: (id: string) => void;
  onCreate: () => void;
  onDelete: (id: string) => void;
}) {
  const [query, setQuery] = useState("");
  const shown = useSearch(core, recipes, query);
  return (
    <div className="tab-page pushed" data-page="recipes">
      <NavBar title={t("menu.recipes")} back={t("menu.title")} onBack={onBack} large />
      <SearchField query={query} onChange={setQuery} testID="menu.recipes.search" />
      <List>
        <ListSection>
          <ListRow onClick={onCreate}>
            <span className="inline-action" data-testid="menu.recipe.new">
              <Plus aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("menu.recipe.new")}</span>
            </span>
          </ListRow>
        </ListSection>
        <ListSection>
          {shown.map((recipe) => {
            const row = (
              <button type="button" className="list-row list-row-button" data-testid={`menu.recipe.${recipe.id}`} onClick={() => onOpen(recipe.id)}>
                <RecipeRow recipe={recipe} />
              </button>
            );
            return recipe.own ? (
              <SwipeRow key={recipe.id} bare name={recipe.title} deleteLabel={t("menu.recipe.delete")} onDelete={() => onDelete(recipe.id)}>
                {row}
              </SwipeRow>
            ) : (
              <Fragment key={recipe.id}>{row}</Fragment>
            );
          })}
        </ListSection>
      </List>
    </div>
  );
}

function Labeled({ label, children }: { label: string; children: ReactNode }) {
  return (
    <ListRow>
      <span className="labeled">
        <span>{label}</span>
        {children}
      </span>
    </ListRow>
  );
}

/** One recipe: its photo with the maker's credit, energy and macros per serving, ingredients and steps (RecipeDetailView). */
export function RecipeDetail({ rows, recipe, back, onBack }: { rows: MenuRows; recipe: RecipeSummary; back: string; onBack: () => void }) {
  const values = [...rows.recipes, ...rows.removedRecipes].find((candidate) => candidate.id === recipe.id);
  const [ingredients, setIngredients] = useState<Ingredient[]>();
  const [photoShown, setPhotoShown] = useState(!recipe.own);
  const credit = recipe.own ? undefined : photoCredits[recipe.id];
  const steps = recipeSteps(rows.steps[recipe.id] ?? {});
  const languages = navigator.languages;

  useEffect(() => {
    let current = true;
    recipeIngredients(supabase, recipe.id).then(
      (found) => current && setIngredients(found),
      () => current && setIngredients([]),
    );
    return () => {
      current = false;
    };
  }, [recipe.id]);

  const grams = (value: number) => <span className="tabular">{`${decimal(value, 1)} g`}</span>;
  const name = (localized: Record<string, string>) =>
    [...languages.map((tag) => tag.slice(0, 2)), "en", "nl"].map((lang) => localized[lang]).find(Boolean) ?? Object.values(localized)[0] ?? "";

  return (
    <div className="tab-page pushed" data-page="recipe">
      <NavBar title={recipe.title} back={back} onBack={onBack} />
      <List>
        {photoShown && (
          <ListSection footer={credit ? t("menu.photo.credit %@ %@", credit.author, credit.licence) : undefined}>
            <img className="recipe-photo" src={photoURL(recipe.id)} alt="" onError={() => setPhotoShown(false)} />
          </ListSection>
        )}
        {values && (
          <ListSection header={t("menu.recipe.perServing")} footer={recipe.own ? undefined : t("menu.recipe.source")}>
            <Labeled label={t("menu.recipe.kcal")}>
              <span className="value" data-testid="menu.recipe.kcal">
                {kcal(Math.round(values.kcalPerServing))}
              </span>
            </Labeled>
            <Labeled label={t("targets.protein")}>{grams(values.proteinGPerServing)}</Labeled>
            <Labeled label={t("targets.carbs")}>{grams(values.carbsGPerServing)}</Labeled>
            <Labeled label={t("targets.fat")}>{grams(values.fatGPerServing)}</Labeled>
          </ListSection>
        )}
        <ListSection header={t("menu.recipe.ingredients %lld", values?.servings ?? 1)}>
          {ingredients === undefined ? (
            <ListRow>
              <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
            </ListRow>
          ) : (
            ingredients.map((ingredient, index) => (
              <ListRow key={index}>
                <span className="labeled">
                  <span>{name(ingredient.name)}</span>
                  <span className="secondary tabular">{amountText(ingredient.quantity, ingredient.unit)}</span>
                </span>
              </ListRow>
            ))
          )}
        </ListSection>
        {steps.length > 0 && (
          <ListSection header={t("menu.recipe.steps")}>
            {steps.map((step, index) => (
              <ListRow key={index}>
                <span className="recipe-step">
                  <span className="recipe-step-number tabular">{index + 1}</span>
                  <span>{step}</span>
                </span>
              </ListRow>
            ))}
          </ListSection>
        )}
      </List>
    </div>
  );
}

const units = ["g", "ml", "piece", "tbsp", "tsp"] as const;
const unitNames: Record<(typeof units)[number], string> = {
  g: "menu.unitName.g",
  ml: "menu.unitName.ml",
  piece: "menu.unitName.piece",
  tbsp: "menu.unitName.tbsp",
  tsp: "menu.unitName.tsp",
};

/**
 * A recipe of the user's own: title, servings, time, meals, energy and macros per serving, and the ingredients for the
 * shopping list (OwnRecipeForm). It can be saved once FitlingCore finds it complete.
 */
export function OwnRecipeForm({
  core,
  userID,
  onSaved,
  onCancel,
  onFailed,
}: {
  core: FitlingCore;
  userID: string;
  onSaved: () => void;
  onCancel: () => void;
  onFailed: (message: string) => void;
}) {
  const [title, setTitle] = useState("");
  const [servings, setServings] = useState(2);
  const [cookMinutes, setCookMinutes] = useState(30);
  const [slots, setSlots] = useState<string[]>(["dinner"]);
  const [numbers, setNumbers] = useState({ kcal: "", protein: "", carbs: "", fat: "" });
  const [lines, setLines] = useState<OwnRecipe["ingredients"]>([]);
  const [line, setLine] = useState({ name: "", quantity: "", unit: "g" as string });
  const [saving, setSaving] = useState(false);

  const own: OwnRecipe = {
    title,
    servings,
    cookMinutes,
    kcal: parseNumber(numbers.kcal),
    protein: parseNumber(numbers.protein),
    carbs: parseNumber(numbers.carbs),
    fat: parseNumber(numbers.fat),
    mealSlots: slots,
    ingredients: lines,
    steps: [],
  };
  const complete = core.ownRecipeComplete({
    title,
    servings,
    cookMinutes,
    kcal: own.kcal,
    protein: own.protein,
    carbs: own.carbs,
    fat: own.fat,
    mealSlots: mealSlots.filter((slot) => slots.includes(slot)),
  }).complete;

  // One id for every try: saving again after a failure does not make a second recipe.
  const [recipeID] = useState(() => crypto.randomUUID());

  async function save() {
    if (!complete || saving) return;
    setSaving(true);
    try {
      await createRecipe(supabase, userID, own, typingLanguage(), new Date(), recipeID);
      onSaved();
    } catch (error) {
      setSaving(false);
      onFailed(error instanceof Error ? error.message : "error.server");
    }
  }

  function addLine() {
    const typed = parseNumber(line.quantity);
    // As recipe_ingredients keeps it: 0,004 g would be refused there (MenuBook.storedIngredientQuantity).
    const quantity = typed === undefined ? undefined : core.storedIngredientQuantity({ quantity: typed }).quantity;
    const name = line.name.trim();
    if (quantity === undefined || name === "") return;
    setLines([...lines, { id: crypto.randomUUID(), name, quantity, unit: line.unit }]);
    setLine({ ...line, name: "", quantity: "" });
  }

  const numberRow = (field: keyof typeof numbers, label: string, unit: string) => (
    <ListRow>
      <label className="labeled">
        <span>{label}</span>
        <span className="value-input">
          <input
            className="text-field tabular number-input"
            inputMode="decimal"
            placeholder={label}
            data-testid={`menu.own.${field}`}
            value={numbers[field]}
            onChange={(event) => setNumbers({ ...numbers, [field]: event.target.value })}
          />
          <span className="secondary">{unit}</span>
        </span>
      </label>
    </ListRow>
  );

  return (
    <FormSheet title={t("menu.recipe.new")} saveLabel={t("common.save")} canSave={complete && !saving} onSave={() => void save()} onCancel={onCancel}>
      <ListSection>
        <ListRow>
          <input
            className="text-field"
            placeholder={t("menu.own.title")}
            aria-label={t("menu.own.title")}
            data-testid="menu.own.title"
            value={title}
            onChange={(event) => setTitle(event.target.value)}
          />
        </ListRow>
        <ListRow>
          <Stepper label={t("menu.own.servings %lld", servings)} value={servings} min={1} max={20} onChange={setServings} />
        </ListRow>
        <ListRow>
          <Stepper label={t("menu.own.minutes %lld", cookMinutes)} value={cookMinutes} min={0} max={600} step={5} onChange={setCookMinutes} />
        </ListRow>
      </ListSection>
      <ListSection header={t("menu.own.meals")}>
        {mealSlots.map((slot) => (
          <ListRow key={slot}>
            <label className="toggle-row">
              <span>{t(`meal.${slot}`)}</span>
              <input
                type="checkbox"
                role="switch"
                className="switch"
                data-testid={`menu.own.slot.${slot}`}
                checked={slots.includes(slot)}
                onChange={(event) => setSlots(event.target.checked ? [...slots, slot] : slots.filter((chosen) => chosen !== slot))}
              />
            </label>
          </ListRow>
        ))}
      </ListSection>
      <ListSection header={t("menu.recipe.perServing")} footer={t("menu.own.values.footer")}>
        {numberRow("kcal", t("menu.own.kcal"), "kcal")}
        {numberRow("protein", t("targets.protein"), "g")}
        {numberRow("carbs", t("targets.carbs"), "g")}
        {numberRow("fat", t("targets.fat"), "g")}
      </ListSection>
      <ListSection header={t("menu.recipe.ingredients.title")}>
        {lines.map((entry, index) => (
          <SwipeRow key={index} name={entry.name} deleteLabel={t("menu.recipe.delete")} onDelete={() => setLines(lines.filter((_, other) => other !== index))}>
            <span>{`${amountText(entry.quantity, entry.unit)} ${entry.name}`}</span>
          </SwipeRow>
        ))}
        <ListRow>
          <span className="ingredient-fields">
            <input
              className="text-field"
              placeholder={t("menu.own.ingredient")}
              aria-label={t("menu.own.ingredient")}
              data-testid="menu.own.ingredient"
              value={line.name}
              onChange={(event) => setLine({ ...line, name: event.target.value })}
            />
            <input
              className="text-field tabular ingredient-quantity"
              inputMode="decimal"
              placeholder={t("menu.own.quantity")}
              aria-label={t("menu.own.quantity")}
              data-testid="menu.own.quantity"
              value={line.quantity}
              onChange={(event) => setLine({ ...line, quantity: event.target.value })}
            />
          </span>
        </ListRow>
        <PickerRow
          label={t("menu.own.unit")}
          value={line.unit}
          options={units.map((unit) => [unit, t(unitNames[unit])])}
          onChange={(unit: string) => setLine({ ...line, unit })}
        />
        <ListRow onClick={addLine}>
          <span className="inline-action" data-testid="menu.own.addIngredient">
            {t("menu.own.addIngredient")}
          </span>
        </ListRow>
      </ListSection>
    </FormSheet>
  );
}
