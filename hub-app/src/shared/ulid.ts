import { ulid as generate } from "ulidx";

export function newUlid(): string {
  return generate();
}
