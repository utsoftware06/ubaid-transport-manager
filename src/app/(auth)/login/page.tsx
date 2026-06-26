export default function LoginPage() {
  return (
    <main className="min-h-screen flex items-center justify-center bg-gray-100 p-8 text-gray-900">
      <div className="bg-white p-10 rounded-2xl shadow-lg border border-gray-200 w-full max-w-xl">
        <h1 className="text-5xl font-bold text-center text-gray-900 mb-10">
          UT Software Login
        </h1>

        <form className="space-y-6">
          <input
            type="email"
            placeholder="Email"
            className="w-full border border-gray-300 p-5 rounded-xl bg-white text-xl text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          <input
            type="password"
            placeholder="Password"
            className="w-full border border-gray-300 p-5 rounded-xl bg-white text-xl text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />

          <button
            type="submit"
            className="w-full bg-blue-600 hover:bg-blue-700 text-white text-2xl font-semibold p-5 rounded-xl transition"
          >
            Login
          </button>
        </form>
      </div>
    </main>
  );
}

