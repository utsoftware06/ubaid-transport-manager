"use client";

import { useState } from "react";
import { supabase } from "@/lib/supabase/client";

export default function RegisterPage() {
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  async function handleRegister(
    e: React.FormEvent<HTMLFormElement>
  ) {
    e.preventDefault();

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
    });

    if (error) {
      alert(error.message);
      return;
    }

    const user = data.user;

    if (user) {
      const { error: profileError } = await supabase
        .from("profiles")
        .insert({
          id: user.id,
          full_name: fullName,
          role: "super_admin",
        });

      if (profileError) {
        alert(profileError.message);
        return;
      }
    }

    alert("UT Software account created successfully!");

    setFullName("");
    setEmail("");
    setPassword("");
  }

  return (
    <main className="min-h-screen flex items-center justify-center bg-slate-100 p-8">
      <div className="bg-white p-10 rounded-2xl shadow-lg w-full max-w-xl">
        <h1 className="text-5xl font-bold text-center text-slate-900 mb-10">
          Create UT Software Account
        </h1>

        <form
          onSubmit={handleRegister}
          className="space-y-6"
        >
          <input
            type="text"
            placeholder="Full Name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            className="w-full border border-slate-300 p-5 rounded-xl text-xl text-slate-700 placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-green-500"
            required
          />

          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full border border-slate-300 p-5 rounded-xl text-xl text-slate-700 placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-green-500"
            required
          />

          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full border border-slate-300 p-5 rounded-xl text-xl text-slate-700 placeholder:text-slate-500 focus:outline-none focus:ring-2 focus:ring-green-500"
            required
            minLength={6}
          />

          <button
            type="submit"
            className="w-full bg-green-600 text-white text-2xl font-semibold p-5 rounded-xl hover:bg-green-700 transition"
          >
            Create Account
          </button>
        </form>
      </div>
    </main>
  );
}