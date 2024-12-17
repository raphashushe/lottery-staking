import React from "react";

const Sidebar = () => {
  return (
    <div className="w-64 bg-gray-800 p-6">
      <h1 className="text-2xl font-bold mb-8 text-yellow-400">Lucky Larry</h1>
      <nav className="space-y-6">
        <a href="#" className="block text-lg hover:text-yellow-400 transition">
          Home
        </a>
        <a href="#" className="block text-lg hover:text-yellow-400 transition">
          How It Works
        </a>
        <a href="#" className="block text-lg hover:text-yellow-400 transition">
          Tiers
        </a>
        <a href="#" className="block text-lg hover:text-yellow-400 transition">
          Join Lottery
        </a>
        <a href="#" className="block text-lg hover:text-yellow-400 transition">
          Results
        </a>
      </nav>
    </div>
  );
};

export default Sidebar;
