import React from "react";

const Homepage = () => {
  return (
    <div className="flex-1 p-10">
      <div className="text-center">
        <h1 className="text-4xl font-extrabold text-yellow-400 animate-bounce">
          Decentralized Lottery
        </h1>
        <p className="text-lg text-gray-300 mt-4">
          Stake tokens and win exciting rewards in our fair and transparent lottery!
        </p>
      </div>
      <div className="flex justify-center mt-10">
        <div className="max-w-2xl p-8 bg-gray-800 rounded-lg shadow-lg text-center">
          <h2 className="text-2xl font-bold text-yellow-400">How It Works</h2>
          <p className="text-gray-300 mt-4">
            1. Stake tokens to enter the lottery.<br />
            2. At the end of the cycle, a random winner is selected.<br />
            3. Non-winners share part of the pool as rewards.
          </p>
          <button className="mt-6 px-6 py-2 bg-yellow-400 text-gray-900 font-semibold rounded-md hover:bg-yellow-500 transition">
            Join Now
          </button>
        </div>
      </div>
    </div>
  );
};

export default Homepage;
