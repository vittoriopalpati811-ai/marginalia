import { redirect } from "next/navigation";

// Root → redirect to library (middleware handles auth)
export default function Home() {
  redirect("/library");
}
