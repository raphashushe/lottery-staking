import { useState } from 'react';
import reactLogo from './assets/react.svg';
import './App.css';
import * as MicroStacks from '@micro-stacks/react';
import { WalletConnectButton } from './components/wallet-connect-button.jsx';
import { UserCard } from './components/user-card.jsx';
import { Logo } from './components/ustx-logo.jsx';
import { NetworkToggle } from './components/network-toggle.jsx';

import React from "react";
import Sidebar from "./components/Sidebar";
import Homepage from "./components/Homepage";

function Contents() {
  return (
    <>
      
      <div class="card">
        <UserCard />
        <WalletConnectButton />
        <NetworkToggle />
      </div>
    </>
  );
}

export default function App() {
  return (
    <MicroStacks.ClientProvider
      appName={'React + micro-stacks'}
      appIconUrl={reactLogo}
    >
      {/* <Contents /> */}
      <div className="flex h-screen bg-gray-900 text-white">
      <Sidebar />
      <Homepage />
    </div>
    </MicroStacks.ClientProvider>
  );
}
