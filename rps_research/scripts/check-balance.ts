import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

async function checkBalance() {
    const address = process.env.SUI_ADDRESS;
    
    if (!address) {
        console.error('❌ No SUI_ADDRESS found in .env file');
        console.error('Run: npm run setup-account first');
        process.exit(1);
    }

    const suiClient = new SuiClient({ 
        url: getFullnodeUrl('testnet') 
    });

    console.log(`\n🔍 Checking balance for: ${address}\n`);

    try {
        // Get SUI balance
        const balance = await suiClient.getBalance({
            owner: address,
        });

        const suiAmount = Number(balance.totalBalance) / 1_000_000_000;
        
        console.log('💰 Balance Information:');
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        console.log(`Total Balance: ${balance.totalBalance} MIST`);
        console.log(`Total Balance: ${suiAmount} SUI`);
        console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

        if (suiAmount === 0) {
            console.log('⚠️  Your account needs funding!');
            console.log('Visit: https://suiexplorer.com/');
            console.log(`Use address: ${address}`);
        } else {
            console.log('✅ Account is funded and ready for deployment!');
        }

        // Get all coin objects
        const coins = await suiClient.getCoins({
            owner: address,
        });

        if (coins.data.length > 0) {
            console.log(`\n📊 Coin objects: ${coins.data.length}`);
            coins.data.forEach((coin, index) => {
                console.log(`  ${index + 1}. ${coin.coinObjectId.substring(0, 16)}... : ${Number(coin.balance) / 1_000_000_000} SUI`);
            });
        }

    } catch (error) {
        console.error('Error checking balance:', error);
    }
}

// Run the check
checkBalance().catch(console.error);