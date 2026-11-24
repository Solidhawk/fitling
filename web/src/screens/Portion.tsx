import { Star } from "lucide-react";
import { useEffect, useState } from "react";
import type { FitlingCore, QuantityUnit } from "../core/fitlingCore";
import { isFavorite, logProduct, type Meal, setFavorite } from "../data/diary";
import { ownCopy, type Product, productName } from "../data/products";
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
  const [favorite, setFavoriteState] = useState(false);
  const [saving, setSaving] = useState(false);
  const [failed, setFailed] = useState<string>();
  const name = productName(core, product);

  useEffect(() => {
    void isFavorite(supabase, product.id).then(setFavoriteState, () => undefined);
  }, [product.id]);

  const quantity = parseNumber(quantityText);
  const kcalOnPackage = parseNumber(kcalText);
  const portion = core.portion({ quantityUnit: product.quantityUnit, servingSize: product.servingSize, per100, quantity, unit, kcalOnPackage });
  const hasUnknownMacros = product.protein100 === undefined || product.carbs100 === undefined || product.fat100 === undefined;

  async function toggleFavorite() {
    try {
      await setFavorite(supabase, userID, product.id, !favorite, new Date());
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
      // Without kcal the shared product stays as it is; the user's own copy gets the kcal from the package.
      const logged = portion.needsKcal && kcalOnPackage !== undefined ? await ownCopy(supabase, userID, product, kcalOnPackage, new Date()) : product;
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
          <button type="button" className="nav-back nav-action icon-button" aria-label={t(favorite ? "portion.favorite.remove" : "portion.favorite.add")} aria-pressed={favorite} onClick={() => void toggleFavorite()}>
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
        <ListSection footer={servingFooter}>
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
              value={quantityText}
              onChange={(event) => setQuantityText(event.target.value)}
            />
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
        <ListSection footer={failed ? <span className="message">{t(failed)}</span> : undefined}>
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
