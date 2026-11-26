import { useState } from "react";
import { decimal } from "../format";
import { t } from "../i18n";

/** The first letter or digit of the name, upper case; a dash when there is none (ProductThumbnail.initial). */
export function initial(name: string): string {
  return Array.from(name).find((character) => /[\p{L}\p{N}]/u.test(character))?.toUpperCase() ?? "–";
}

/** The package photo, or the first letter on a pale tile while there is none (ProductThumbnail.swift). */
export function ProductThumbnail({ imageURL, name, size = 44 }: { imageURL?: string; name: string; size?: number }) {
  const [failed, setFailed] = useState(false);
  const style = { width: size, height: size, borderRadius: size / 4 };
  if (imageURL && !failed) {
    return <img className="thumbnail" src={imageURL} alt="" style={style} loading="lazy" onError={() => setFailed(true)} />;
  }
  return (
    <span className="thumbnail thumbnail-placeholder" aria-hidden="true" style={{ ...style, fontSize: size * 0.45 }}>
      {initial(name)}
    </span>
  );
}

/** A product in a list: photo, name, brand, and kcal per 100 g or ml (ProductRow in LogFoodView.swift). */
export function ProductRow({
  name,
  brand,
  kcal100,
  unit,
  imageURL,
  onClick,
}: {
  name: string;
  brand?: string;
  kcal100?: number;
  unit: string;
  imageURL?: string;
  onClick: () => void;
}) {
  return (
    <button type="button" className="list-row list-row-button product-row" onClick={onClick}>
      <ProductThumbnail imageURL={imageURL} name={name} />
      <span className="entry-text">
        <span>{name}</span>
        {brand && <span className="footnote secondary">{brand}</span>}
      </span>
      {kcal100 !== undefined && <span className="footnote secondary tabular">{t("log.kcalPer100 %@ %@", decimal(kcal100, 0), unit)}</span>}
    </button>
  );
}
