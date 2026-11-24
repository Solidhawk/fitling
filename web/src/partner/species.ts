/** The sixteen partners, in the order of Species.allCases in FitlingCore. */
export const species = [
  "bumblebee", "mole", "frog", "owl", "hedgehog", "snail", "axolotl", "seal",
  "penguin", "turtle", "rabbit", "raccoon", "ladybird", "octopus", "squirrel", "lamb",
] as const;

export type Species = (typeof species)[number];
