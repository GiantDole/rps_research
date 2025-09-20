import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import * as fs from 'fs';
import * as path from 'path';

async function setupAccount() {
    console.log('🔐 Creating new Sui testnet account...\n');

    // Generate a new keypair
    const keypair = new Ed25519Keypair();
    
    // Get the address
    const address = keypair.toSuiAddress();
    
    // Get the private key (without 0x prefix for compatibility)
    const privateKey = keypair.getSecretKey();
    const privateKeyHex = '0x' + Buffer.from(privateKey).toString('hex');
    
    // Get the public key
    const publicKey = keypair.getPublicKey();
    const publicKeyBase64 = publicKey.toBase64();

    // Initialize Sui client to check balance
    const suiClient = new SuiClient({ 
        url: getFullnodeUrl('testnet') 
    });

    console.log('✅ Account created successfully!\n');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('ACCOUNT DETAILS:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`Address: ${address}`);
    console.log(`Private Key: ${privateKeyHex}`);
    console.log(`Public Key (Base64): ${publicKeyBase64}`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    // Check initial balance
    try {
        const balance = await suiClient.getBalance({
            owner: address,
        });
        console.log(`Current balance: ${balance.totalBalance} MIST (${Number(balance.totalBalance) / 1_000_000_000} SUI)\n`);
    } catch (error) {
        console.log('Current balance: 0 SUI (unfunded)\n');
    }

    // Prepare .env content
    const envContent = `# Sui Configuration
SUI_NETWORK=testnet
PRIVATE_KEY=${privateKeyHex}
SUI_ADDRESS=${address}

# Game Configuration (will be filled after deployment)
PACKAGE_ID=
GAME_ID=

# Seal Configuration
SEAL_NETWORK=testnet
`;

    // Update .env file
    const envPath = path.join(process.cwd(), '.env');
    fs.writeFileSync(envPath, envContent);
    console.log('📁 .env file updated with new account details\n');

    // Save account details to a separate file for backup
    const accountDetails = {
        address,
        privateKey: privateKeyHex,
        publicKey: publicKeyBase64,
        network: 'testnet',
        createdAt: new Date().toISOString()
    };

    const accountPath = path.join(process.cwd(), 'testnet-account.json');
    fs.writeFileSync(accountPath, JSON.stringify(accountDetails, null, 2));
    console.log('📁 Account details saved to testnet-account.json\n');

    console.log('🚰 TO FUND YOUR ACCOUNT:');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('1. Go to: https://suiexplorer.com/');
    console.log('2. Make sure you\'re on TESTNET (top right)');
    console.log('3. Click "Request Testnet SUI" button');
    console.log(`4. Paste this address: ${address}`);
    console.log('5. Complete the captcha and request tokens\n');
    
    console.log('Alternative faucet:');
    console.log('https://faucet.triangleplatform.com/sui/testnet');
    console.log(`Address to fund: ${address}\n`);

    console.log('💡 After funding, run: npm run check-balance');
}

// Run the setup
setupAccount().catch(console.error);