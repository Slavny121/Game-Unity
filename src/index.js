import app from './firebase.js';
import Shop from './components/Shop.js';
import VipShop from './components/VipShop.js';
import CustomItems from './components/CustomItems.js';
import Avatars from './components/Avatars.js';
import Profile from './components/Profile.js';
import Friends from './components/Friends.js';
import AdminPanel from './components/AdminPanel.js';

console.log('Firebase app initialized:', app);

const root = document.getElementById('root');

// Basic component rendering
const render = () => {
    root.innerHTML = `
        <h1>Welcome to Clicker v2</h1>
        ${Shop()}
        ${VipShop()}
        ${CustomItems()}
        ${Avatars()}
        ${Profile()}
        ${Friends()}
        <hr>
        ${AdminPanel()}
    `;
};

render();
