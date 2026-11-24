import { useState } from "react";
import type { FitlingCore } from "../core/fitlingCore";
import { addOwnProduct, type Product } from "../data/products";
import { supabase } from "../data/supabase";
import { parseNumber } from "../format";
import { language, t } from "../i18n";
import { PrimaryButton } from "../ui/Buttons";
import { List, ListRow, ListSection } from "../ui/List";
import { NavBar } from "../ui/NavBar";
import { Segmented } from "../ui/Segmented";

type Field = "kcal" | "protein" | "carbs" | "fat" | "servingSize";

/**
 * A product the user types in from the package: private to them, and logged like any other (AddProductView.swift).
 * The checks and rounding are FitlingCore's, the same as on the iPhone.
 */
export function AddProduct({
  core,
  userID,
  gtin = "",
  back,
  onBack,
  onSaved,
}: {
  core: FitlingCore;
  userID: string;
  gtin?: string;
  back: string;
  onBack: () => void;
  onSaved: (product: Product) => void;
}) {
  const [name, setName] = useState("");
  const [brand, setBrand] = useState("");
  const [barcode, setBarcode] = useState(gtin);
  const [isMillilitre, setIsMillilitre] = useState(false);
  const [numbers, setNumbers] = useState<Record<Field, string>>({ kcal: "", protein: "", carbs: "", fat: "", servingSize: "" });
  const [saving, setSaving] = useState(false);
  const [failed, setFailed] = useState<string>();

  const { fields } = core.ownProduct({
    name,
    brand,
    gtin: barcode,
    isMillilitre,
    kcal: parseNumber(numbers.kcal),
    protein: parseNumber(numbers.protein),
    carbs: parseNumber(numbers.carbs),
    fat: parseNumber(numbers.fat),
    servingSize: parseNumber(numbers.servingSize),
  });

  async function save() {
    if (!fields) return;
    setSaving(true);
    setFailed(undefined);
    try {
      onSaved(await addOwnProduct(supabase, userID, fields, language(), new Date()));
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
      setSaving(false);
    }
  }

  const numberRow = (field: Field, key: string, id: string) => (
    <ListRow key={field}>
      <input
        className="text-field tabular"
        inputMode="decimal"
        placeholder={t(key)}
        aria-label={t(key)}
        data-testid={id}
        value={numbers[field]}
        onChange={(event) => setNumbers({ ...numbers, [field]: event.target.value })}
      />
    </ListRow>
  );
  const textRow = (key: string, value: string, onChange: (value: string) => void, id?: string, inputMode?: "numeric") => (
    <ListRow>
      <input
        className="text-field"
        inputMode={inputMode}
        placeholder={t(key)}
        aria-label={t(key)}
        data-testid={id}
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </ListRow>
  );

  return (
    <div className="sheet-page" data-page="addProduct">
      <NavBar title={t("product.add.title")} back={back} onBack={onBack} />
      <List>
        <ListSection>
          {textRow("product.add.name", name, setName, "product.add.name")}
          {textRow("product.add.brand", brand, setBrand)}
          {textRow("product.add.barcode", barcode, setBarcode, "product.add.barcode", "numeric")}
        </ListSection>
        <ListSection header={<span className="header-plain">{t("product.add.per100")}</span>}>
          <ListRow>
            <Segmented
              label={t("portion.unit")}
              value={isMillilitre ? "ml" : "g"}
              options={[
                ["g", t("portion.unit.gram")],
                ["ml", t("portion.unit.millilitre")],
              ]}
              onChange={(value) => setIsMillilitre(value === "ml")}
            />
          </ListRow>
          {numberRow("kcal", "product.add.kcal", "product.add.kcal")}
          {numberRow("protein", "product.add.protein", "product.add.protein")}
          {numberRow("carbs", "product.add.carbs", "product.add.carbs")}
          {numberRow("fat", "product.add.fat", "product.add.fat")}
        </ListSection>
        <ListSection footer={t("product.add.serving.footer")}>{numberRow("servingSize", "product.add.serving", "product.add.serving")}</ListSection>
        <ListSection footer={failed ? <span className="message">{t(failed)}</span> : t("product.add.rules")}>
          <div className="button-row">
            <PrimaryButton disabled={!fields || saving} data-testid="product.add.save" onClick={() => void save()}>
              {t("product.add.save")}
              {saving && <span className="spinner" aria-hidden="true" />}
            </PrimaryButton>
          </div>
        </ListSection>
      </List>
    </div>
  );
}
