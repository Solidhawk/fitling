import { Star } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { FitlingCore, QuantityUnit } from "../core/fitlingCore";
import { isFavorite, keptFavorite, logProduct, type Meal, setFavorite } from "../data/diary";
import { ownCopy, type Product, productName, setOwnKcal } from "../data/products";
import { supabase } from "../data/supabase";
import { decimal, grams, kcal, parseNumber } from "../format";
import { t } from "../i18n";
import { PrimaryButton } from "../ui/Buttons";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { ProductThumbnail } from "../ui/ProductRow";
import { Segmented } from "../ui/Segmented";

const unitKeys: Record<QuantityUnit, string> = { g: "portion.unit.gram", ml: "portion.unit.millilitre", serving: "portion.unit.serving" };

/**
 * How much of one product: grams or millilitres, or servings when the product has a serving size. A product without
 * kcal first asks for the kcal on the package, and is then kept as the user's own copy (PortionView.swift).
 */
export function Portion({
  core,
  userID,
  product,
  meal,
  day,
  back,
  onBack,
  onSaved,
}: {
  core: FitlingCore;
  userID: string;
  product: Product;
  meal: Meal;
  day: string;
  back: string;
  onBack: () => void;
  onSaved: () => void;
}) {
  const per100 = { kcal: product.kcal100, proteinG: product.protein100, carbsG: product.carbs100, fatG: product.fat100 };
  const start = core.portion({ quantityUnit: product.quantityUnit, servingSize: product.servingSize, per100 });
  const [unit, setUnit] = useState<QuantityUnit>(start.defaultUnit);
  const [quantityText, setQuantityText] = useState(decimal(start.defaultQuantity, 1));
  const [kcalText, setKcalText] = useState("");
  // What this browser knew last shows at once, as on the iPhone where the favourite is on the device; the server's
  // answer replaces it, unless the user tapped the star first (UNFORGET S56). When this browser never knew, the star waits
  // for that answer; a read that fails leaves it off, to be set.
  const [favorite, setFavoriteState] = useState(() => keptFavorite(product.id));
  const tapped = useRef(false);
  /** The user's own copy once made, so a retry after a failure does not make another. */
  const [copy, setCopy] = useState<Product>();
  const [saving, setSaving] = useState(false);
  const [failed, setFailed] = useState<string>();
  const name = productName(core, product);

  useEffect(() => {
    let current = true;
    void isFavorite(supabase, product.id).then(
      (known) => current && !tapped.current && setFavoriteState(known),
      () => current && !tapped.current && setFavoriteState((shown) => shown ?? false),
    );
    return () => {
      current = false;
    };
  }, [product.id]);

  const quantity = parseNumber(quantityText);
  const kcalOnPackage = parseNumber(kcalText);
  const answer = core.portion({ quantityUnit: product.quantityUnit, servingSize: product.servingSize, per100, quantity, unit, kcalOnPackage });
  // An empty or unreadable amount is no portion: nothing to show, nothing to save (the field on iOS stays nil).
  const portion = quantity === undefined ? { ...answer, preview: undefined, canSave: false } : answer;
  const hasUnknownMacros = product.protein100 === undefined || product.carbs100 === undefined || product.fat100 === undefined;
  const problemText = portion.problem && t(portion.problem === "tooLittle" ? "portion.tooLittle" : "portion.tooMuch");

  async function toggleFavorite() {
    if (favorite === undefined) return;
    try {
      await setFavorite(supabase, userID, product, !favorite, new Date());
      tapped.current = true;
      setFavoriteState(!favorite);
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
  }

  async function save() {
    if (!portion.canSave || quantity === undefined) return;
    setSaving(true);
    setFailed(undefined);
    try {
      // Without kcal the shared product stays as it is; the user's own copy gets the kcal from the package. A retry
      // uses the copy made the first time, with the kcal as they are typed now.
      let logged = product;
      if (portion.needsKcal && kcalOnPackage !== undefined) {
        logged = !copy
          ? await ownCopy(supabase, userID, product, kcalOnPackage, new Date())
          : copy.kcal100 === kcalOnPackage
            ? copy
            : await setOwnKcal(supabase, copy, kcalOnPackage, new Date());
        setCopy(logged);
      }
      await logProduct(supabase, core, { userID, product: logged, quantity, unit, meal, day, now: new Date() });
      onSaved();
    } catch (error) {
      // The portion stays as it was typed, to try again.
      setFailed(error instanceof Error ? error.message : "error.server");
    } finally {
      setSaving(false);
    }
  }

  const amount = product.servingSize !== undefined ? `${decimal(product.servingSize, 1)} ${product.quantityUnit}` : undefined;
  const servingFooter =
    unit === "serving" && amount
      ? product.servingLabel
        ? t("portion.serving.labelled %@ %@", product.servingLabel, amount)
        : t("portion.serving.size %@", amount)
      : undefined;

  return (
    <div className="sheet-page" data-page="portion">
      <NavBar
        title={name}
        back={back}
        onBack={onBack}
        trailing={
          <button type="button" className="nav-back nav-action icon-button" aria-label={t(favorite ? "portion.favorite.remove" : "portion.favorite.add")} aria-pressed={favorite === true} disabled={favorite === undefined} onClick={() => void toggleFavorite()}>
            <Star aria-hidden="true" size={22} strokeWidth={2.2} fill={favorite ? "currentColor" : "none"} />
          </button>
        }
      />
      <List>
        <ListSection>
          <ListRow>
            <span className="product-header">
              <ProductThumbnail imageURL={product.imageURL} name={name} size={64} />
              <span className="entry-text">
                <span className="product-name">{name}</span>
                {product.brand && <span className="footnote secondary">{product.brand}</span>}
              </span>
            </span>
          </ListRow>
        </ListSection>
        <ListSection
          footer={
            problemText || servingFooter ? (
              <span className="row-stack">
                {/* Save is off for such an amount; this says why (PortionView). Screen readers hear it from the field. */}
                {problemText && (
                  <span data-testid="portion.problem" aria-hidden="true">
                    {problemText}
                  </span>
                )}
                {servingFooter && <span>{servingFooter}</span>}
              </span>
            ) : undefined
          }
        >
          {start.units.length > 1 && (
            <ListRow>
              <Segmented label={t("portion.unit")} value={unit} options={start.units.map((option) => [option, t(unitKeys[option])])} onChange={setUnit} />
            </ListRow>
          )}
          <ListRow>
            <input
              className="text-field number-field"
              inputMode="decimal"
              placeholder={t("portion.quantity")}
              aria-label={t("portion.quantity")}
              data-testid="portion.quantity"
              aria-invalid={problemText !== undefined}
              aria-describedby="portion-problem"
              value={quantityText}
              onChange={(event) => setQuantityText(event.target.value)}
            />
            {/* Always there, so a screen reader announces the line when it appears while typing (VoiceOver on iOS too). */}
            <span id="portion-problem" className="visually-hidden" aria-live="polite">
              {problemText ?? ""}
            </span>
          </ListRow>
        </ListSection>
        {portion.needsKcal && (
          <ListSection footer={t("portion.kcal.why")}>
            <ListRow>
              <input
                className="text-field"
                inputMode="decimal"
                placeholder={t(product.quantityUnit === "ml" ? "portion.kcal.field.ml" : "portion.kcal.field.gram")}
                aria-label={t(product.quantityUnit === "ml" ? "portion.kcal.field.ml" : "portion.kcal.field.gram")}
                data-testid="portion.kcal"
                value={kcalText}
                onChange={(event) => setKcalText(event.target.value)}
              />
            </ListRow>
          </ListSection>
        )}
        {portion.preview && (
          <ListSection footer={hasUnknownMacros ? t("portion.unknownMacros") : undefined}>
            <ListRow>
              <span className="labeled">
                <span>{t("portion.energy")}</span>
                <span className="value" data-testid="portion.energy">
                  {kcal(portion.preview.kcal)}
                </span>
              </span>
            </ListRow>
            {(
              [
                ["targets.protein", portion.preview.proteinG],
                ["targets.carbs", portion.preview.carbsG],
                ["targets.fat", portion.preview.fatG],
              ] as const
            ).map(([key, value]) => (
              <ListRow key={key}>
                <span className="labeled">
                  <span>{t(key)}</span>
                  {value === undefined ? <span className="secondary">{t("portion.unknown")}</span> : <span className="tabular">{grams(value)}</span>}
                </span>
              </ListRow>
            ))}
          </ListSection>
        )}
        <ListSection
          footer={
            failed ? (
              // Said out loud as it appears: Save did not go through.
              <span className="message" role="alert">
                {t(failed)}
              </span>
            ) : undefined
          }
        >
          <div className="button-row">
            <PrimaryButton disabled={!portion.canSave || saving} data-testid="portion.save" onClick={() => void save()}>
              {t("portion.save")}
              {saving && <span className="spinner" aria-hidden="true" />}
            </PrimaryButton>
          </div>
        </ListSection>
      </List>
    </div>
  );
}
