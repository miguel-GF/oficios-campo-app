import { signIn, signUp } from "./actions";

export default async function SignInPage({
  searchParams,
}: {
  searchParams: Promise<{ returnTo?: string }>;
}) {
  const { returnTo = "" } = await searchParams;
  return (
    <main style={{ maxWidth: 420, margin: "64px auto", padding: 24 }}>
      <h1>Cuenta de Jale</h1>
      <p>Inicia sesión o crea tu cuenta para volver de forma segura a la app.</p>
      <form style={{ display: "grid", gap: 12 }}>
        <input type="hidden" name="returnTo" value={returnTo} />
        <label>Correo<input required name="email" type="email" style={{ width: "100%", padding: 12 }} /></label>
        <label>Contraseña<input required minLength={8} name="password" type="password" style={{ width: "100%", padding: 12 }} /></label>
        <button formAction={signIn} style={{ padding: 12 }}>Entrar</button>
        <button formAction={signUp} style={{ padding: 12 }}>Crear cuenta</button>
      </form>
    </main>
  );
}
