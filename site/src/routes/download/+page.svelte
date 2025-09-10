<script lang="ts">
	import { Button } from '$lib/components/ui/button';
	import {
		Card,
		CardContent,
		CardDescription,
		CardHeader,
		CardTitle
	} from '$lib/components/ui/card';
	import { Badge } from '$lib/components/ui/badge';
	import {
		Download,
		Shield,
		Globe,
		Search,
		KeyRound,
		Terminal,
		ExternalLink,
		Github,
		Monitor,
		AppWindow,
	} from 'lucide-svelte';
	import Navbar from '$lib/components/Navbar.svelte';

    const version = '1.0.1';
</script>

<svelte:head>
	<title>Download - Gurted</title>
	<meta
		name="description"
		content="Download Flumi browser and other Gurted ecosystem components for your platform."
	/>
</svelte:head>

<main class="bg-background text-foreground min-h-screen">
	<Navbar />

	<!-- Main Downloads -->
	<section class="px-4 pt-40">
		<div class="container mx-auto max-w-6xl">
			<div class="mb-16 text-center">
				<h2 class="font-gurted mb-4 inline-block align-middle text-4xl font-bold md:text-5xl">
					Flumi
				</h2>
				<Badge variant="secondary" class="ml-2 align-middle">v{version}</Badge>
				<p class="text-muted-foreground mx-auto max-w-3xl text-xl">
					The official wayfinder (browser) for the GURT ecosystem
				</p>
			</div>

			<div class="mb-16 grid gap-8 md:grid-cols-3">
				<!-- Windows -->
				<Card class="text-center transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div
							class="bg-primary/10 mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-2xl"
						>
							<AppWindow class="text-primary h-12 w-12" />
						</div>
						<CardTitle class="text-2xl">Windows</CardTitle>
						<CardDescription>Windows 10/11 (x64)</CardDescription>
					</CardHeader>
					<CardContent class="space-y-4">
						<Button class="w-full" size="lg" href="https://github.com/outpoot/gurted/releases/download/v{version}/Flumi_Setup_Windows.exe" target="_blank" rel="noopener noreferrer">
							<Download class="h-4 w-4 " />
							Download
						</Button>
					</CardContent>
				</Card>

				<!-- macOS -->
				<Card class="text-center transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div
							class="bg-primary/10 mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-2xl"
						>
							<Monitor class="text-primary h-12 w-12" />
						</div>
						<CardTitle class="text-2xl">macOS</CardTitle>
						<CardDescription>macOS 11+ (Universal)</CardDescription>
					</CardHeader>
					<CardContent class="space-y-4">
						<Button class="w-full" size="lg" disabled>
							<Download class="h-4 w-4 "/>
							Download (soon)
						</Button>
					</CardContent>
				</Card>

				<!-- Linux -->
				<Card class="text-center transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div
							class="bg-primary/10 mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-2xl"
						>
							<Terminal class="text-primary h-12 w-12" />
						</div>
						<CardTitle class="text-2xl">Linux</CardTitle>
						<CardDescription>Ubuntu 20.04+ / Fedora 35+</CardDescription>
					</CardHeader>
					<CardContent class="space-y-4">
						<Button class="w-full" size="lg"  href="https://github.com/outpoot/gurted/releases/download/v{version}/Flumi_Linux.tar.gz" target="_blank" rel="noopener noreferrer">
							<Download class="h-4 w-4 " />
							Download
						</Button>
					</CardContent>
				</Card>
			</div>
		</div>
	</section>

	<!-- Ecosystem Tools -->
	<section class="bg-muted/30 px-4 py-10">
		<div class="container mx-auto max-w-6xl">
			<div class="mb-16 text-center">
				<h2 class="font-gurted mb-4 text-4xl font-bold md:text-5xl">Ecosystem Tools</h2>
				<p class="text-muted-foreground mx-auto max-w-3xl text-xl">
					Additional tools and services for developers and server administrators
				</p>
			</div>

			<div class="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
				<!-- GURT Protocol Library -->
				<Card class="transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div class="bg-primary/10 mb-4 flex h-16 w-16 items-center justify-center rounded-2xl">
							<Shield class="text-primary h-8 w-8" />
						</div>
						<CardTitle>GURT Protocol</CardTitle>
					</CardHeader>
					<CardContent class="space-y-4">
						<p class="text-muted-foreground text-sm">
							Implementation libraries for the GURT protocol in multiple languages
						</p>
						<Button variant="outline" class="w-full" href="https://github.com/outpoot/gurted">
							<ExternalLink class="h-4 w-4 " />
							View on GitHub
						</Button>
					</CardContent>
				</Card>

				<!-- GurtDNS Server -->
				<Card class="transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div class="bg-primary/10 mb-4 flex h-16 w-16 items-center justify-center rounded-2xl">
							<Globe class="text-primary h-8 w-8" />
						</div>
						<CardTitle>GurtDNS</CardTitle>
					</CardHeader>
					<CardContent class="space-y-4">
						<p class="text-muted-foreground text-sm">
							Self-hosted DNS server with encrypted queries and domain management
						</p>
						<Button variant="outline" class="w-full" href="https://github.com/outpoot/gurted">
							<ExternalLink class="h-4 w-4 " />
							View Repository
						</Button>
					</CardContent>
				</Card>

				<!-- Ringle Search -->
				<Card class="transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div class="bg-primary/10 mb-4 flex h-16 w-16 items-center justify-center rounded-2xl">
							<Search class="text-primary h-8 w-8" />
						</div>
						<CardTitle>Ringle</CardTitle>
					</CardHeader>
					<CardContent class="space-y-4">
						<p class="text-muted-foreground text-sm">
							Privacy-focused search engine designed for the GURT ecosystem
						</p>
						<Button variant="outline" class="w-full" href="https://github.com/outpoot/gurted">
							<ExternalLink class="h-4 w-4 " />
							View Repository
						</Button>
					</CardContent>
				</Card>

				<!-- GurtCA -->
				<Card class="transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div class="bg-primary/10 mb-4 flex h-16 w-16 items-center justify-center rounded-2xl">
							<KeyRound class="text-primary h-8 w-8" />
						</div>
						<CardTitle>GurtCA</CardTitle>
					</CardHeader>
                    <CardContent class="space-y-4">
						<p class="text-muted-foreground text-sm">
							Automated certificate authority for GURT domains with DNS validation
						</p>
						<Button variant="outline" class="w-full" href="https://github.com/outpoot/gurted">
							<ExternalLink class="h-4 w-4 " />
							View Repository
						</Button>
					</CardContent>
				</Card>

				<!-- Gurty CLI -->
				<Card class="transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div class="bg-primary/10 mb-4 flex h-16 w-16 items-center justify-center rounded-2xl">
							<Terminal class="text-primary h-8 w-8" />
						</div>
						<CardTitle>Gurty CLI</CardTitle>
					</CardHeader>
					<CardContent class="space-y-4">
						<p class="text-muted-foreground text-sm">
							CLI tool for setting up and managing GURT protocol servers
						</p>
						<Button variant="outline" class="w-full" href="https://github.com/outpoot/gurted">
							<ExternalLink class="h-4 w-4 " />
							View Repository
						</Button>
					</CardContent>
				</Card>

				<!-- Source Code -->
				<Card class="transition-all duration-300 hover:shadow-xl">
					<CardHeader>
						<div class="bg-primary/10 mb-4 flex h-16 w-16 items-center justify-center rounded-2xl">
							<Github class="text-primary h-8 w-8" />
						</div>
						<CardTitle>Source Code</CardTitle>
					</CardHeader>
					<CardContent class="space-y-4">
						<p class="text-muted-foreground text-sm">
							All Gurted components are open source and available on GitHub
						</p>
						<Button variant="outline" class="w-full" href="https://github.com/outpoot/gurted">
							<ExternalLink class="h-4 w-4 " />
							View Repository
						</Button>
					</CardContent>
				</Card>
			</div>
		</div>
	</section>
</main>

<style>
	@keyframes fadeInUp {
		from {
			opacity: 0;
			transform: translateY(30px);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}

	.animate-fade-in-up {
		animation: fadeInUp 0.8s ease-out;
	}
</style>
