"use server";

import { redirect } from "next/navigation";
import { auth } from "../../../lib/auth";

function safeReturnTo(value: FormDataEntryValue | null): string {
  const path = typeof value === "string" ? value : "";
  if (!path.startsWith("/mobile?")) throw new Error("Invalid return path");
  return path;
}

export async function signIn(form: FormData) {
  const returnTo = safeReturnTo(form.get("returnTo"));
  const email = String(form.get("email") ?? "").trim().toLowerCase();
  const password = String(form.get("password") ?? "");
  const result = await auth.signIn.email({ email, password });
  if (result.error) throw new Error("No pudimos iniciar sesión");
  redirect(returnTo);
}

export async function signUp(form: FormData) {
  const returnTo = safeReturnTo(form.get("returnTo"));
  const email = String(form.get("email") ?? "").trim().toLowerCase();
  const password = String(form.get("password") ?? "");
  const result = await auth.signUp.email({ email, password, name: email.split("@")[0] });
  if (result.error) throw new Error("No pudimos crear la cuenta");
  redirect(returnTo);
}
