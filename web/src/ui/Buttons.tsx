import type { ButtonHTMLAttributes } from "react";

type Props = ButtonHTMLAttributes<HTMLButtonElement>;

/** The main action: an ink capsule with the label in the card colour (PrimaryButtonStyle). */
export function PrimaryButton({ className, ...props }: Props) {
  return <button type="button" {...props} className={`button button-primary ${className ?? ""}`} />;
}

/** A secondary action: a card-coloured capsule lifted off the ground (SecondaryButtonStyle). */
export function SecondaryButton({ className, ...props }: Props) {
  return <button type="button" {...props} className={`button button-secondary ${className ?? ""}`} />;
}
