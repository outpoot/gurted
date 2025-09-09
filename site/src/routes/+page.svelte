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
		Zap,
		Palette,
		Globe,
		Wrench,
		Rocket,
		ExternalLink,
		Search,
		KeyRound,
		Terminal,
		Server
	} from 'lucide-svelte';
	import Navbar from '$lib/components/Navbar.svelte';
</script>

<svelte:head>
	<title>Gurted</title>
	<meta
		name="description"
		content="A web ecosystem with the gurt:// protocol, custom browser Flumi, DNS system, and modern HTML/CSS/Lua standards."
	/>

	<link href="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/themes/prism-tomorrow.min.css" rel="stylesheet" />
	<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/components/prism-core.min.js"></script>
	<script src="https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/plugins/autoloader/prism-autoloader.min.js"></script>
</svelte:head>

<main class="bg-background text-foreground min-h-screen">
	<Navbar />

	<!-- Hero Section -->
	<section class="px-4 py-20 pt-40">
		<div class="container mx-auto max-w-6xl text-center">
			<div class="animate-fade-in-up">
				<h1 class="text-6xl md:text-9xl lg:text-[8rem] font-bold mb-6 animate-fade-in font-gurted text-gurted-gradient">
					Gurted
				</h1>
				<p class="text-muted-foreground mx-auto mb-4 max-w-3xl text-xl md:text-2xl">
					A web ecosystem introducing the <code
						class="bg-muted text-primary rounded px-2 py-1 font-mono">gurt://</code
					> protocol
				</p>

				<div class="flex flex-col justify-center gap-4 sm:flex-row">
					<Button size="lg" class="px-8 py-6 text-lg" href="/download">
						<Download class="h-5 w-5" />
						Download
					</Button>
					<Button variant="outline" size="lg" class="px-8 py-6 text-lg" href="https://docs.gurted.com">
						<ExternalLink class="h-5 w-5" />
						Documentation
					</Button>
				</div>
			</div>
		</div>
	</section>

	<!-- Ecosystem -->
	<section class="px-4 py-20">
		<div class="container mx-auto max-w-6xl">
			<div class="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
				<Card
					class="animate-float border-border/50 text-center transition-all duration-300 hover:shadow-xl"
					style="animation-delay: 0s;"
				>
					<CardHeader>
						<div
							class="from-primary/20 to-secondary/20 mb-6 flex h-48 w-full items-center justify-center rounded-xl bg-gradient-to-br"
						>
							<img
								src="/crt.gif"
								alt="Flumi wayfinder"
								class="h-full w-full rounded-xl object-cover"
							/>
						</div>
						<CardTitle class="text-2xl">Flumi</CardTitle>
						<CardDescription>The wayfinder (browser)</CardDescription>
					</CardHeader>
					<CardContent>
						<p class="text-muted-foreground">
							Built with the Godot game engine for native performance and features across all platforms, Flumi will light the way.
						</p>
					</CardContent>
				</Card>

				<!-- GURT Protocol -->
				<Card
					class="animate-float border-border/50 text-center transition-all duration-300 hover:shadow-xl"
					style="animation-delay: 0.1s;"
				>
					<CardHeader>
						<div
							class="from-primary/20 to-secondary/20 mb-6 flex h-48 w-full items-center justify-center rounded-xl bg-gradient-to-br"
						>
							<img
								src="/gurtprotocol.jpg"
								alt="GURT Protocol"
								class="h-full w-full rounded-xl object-cover"
							/>
						</div>
						<CardTitle class="text-2xl">GURT Protocol</CardTitle>
						<CardDescription>The protocol</CardDescription>
					</CardHeader>
					<CardContent>
						<p class="text-muted-foreground">
							HTTP-like protocol with mandatory TLS 1.3 encryption, built specifically for Gurted.
						</p>
					</CardContent>
				</Card>

				<Card
					class="animate-float border-border/50 text-center transition-all duration-300 hover:shadow-xl"
					style="animation-delay: 0.2s;"
				>
					<CardHeader>
						<div
							class="from-primary/20 to-secondary/20 mb-6 flex h-48 w-full items-center justify-center rounded-xl bg-gradient-to-br"
						>
							<img
								src="/domains.png"
								alt="GurtDNS"
								class="h-full w-full rounded-xl object-cover"
							/>
						</div>
						<CardTitle class="text-2xl">GurtDNS</CardTitle>
						<CardDescription>The DNS server</CardDescription>
					</CardHeader>
					<CardContent>
						<p class="text-muted-foreground">
							Custom DNS system on GURT with encryption similar to DoH (DNS over HTTPS) and downloadable records.
						</p>
					</CardContent>
				</Card>

				<!-- Ringle Search Engine -->
				<Card
					class="animate-float border-border/50 text-center transition-all duration-300 hover:shadow-xl"
					style="animation-delay: 0.3s;"
				>
					<CardHeader>
						<div
							class="from-primary/20 to-secondary/20 mb-6 flex h-48 w-full items-center justify-center rounded-xl bg-gradient-to-br"
						>
							<img
								src="/ringle.png"
								alt="Ringle Search Engine"
								class="h-full w-full rounded-xl object-cover"
							/>
						</div>
						<CardTitle class="text-2xl">Ringle</CardTitle>
						<CardDescription>The search engine</CardDescription>
					</CardHeader>
					<CardContent>
						<p class="text-muted-foreground">
							Powerful search engine designed specifically for the GURT ecosystem with privacy-first
							approach.
						</p>
					</CardContent>
				</Card>

				<!-- GurtCA -->
				<Card
					class="animate-float border-border/50 text-center transition-all duration-300 hover:shadow-xl"
					style="animation-delay: 0.4s;"
				>
					<CardHeader>
						<div
							class="from-primary/20 to-secondary/20 mb-6 flex h-48 w-full items-center justify-center rounded-xl bg-gradient-to-br"
						>
							<img
								src="/gurtca.png"
								alt="GurtCA Certificate Authority"
								class="h-full w-full rounded-xl object-cover"
							/>
						</div>
						<CardTitle class="text-2xl">GurtCA</CardTitle>
						<CardDescription>The certificate authority</CardDescription>
					</CardHeader>
					<CardContent>
						<p class="text-muted-foreground">
							Certificate authority providing TLS certificates for GURT domains with automated
							validation.
						</p>
					</CardContent>
				</Card>

				<!-- Gurty CLI -->
				<Card
					class="animate-float border-border/50 text-center transition-all duration-300 hover:shadow-xl"
					style="animation-delay: 0.5s;"
				>
					<CardHeader>
						<div
							class="from-primary/20 to-secondary/20 mb-6 flex h-48 w-full items-center justify-center rounded-xl bg-gradient-to-br"
						>
							<img
								src="/gurty.png"
								alt="Gurty CLI Tool"
								class="h-full w-full rounded-xl object-cover"
							/>
						</div>
						<CardTitle class="text-2xl">Gurty</CardTitle>
						<CardDescription>The CLI tool</CardDescription>
					</CardHeader>
					<CardContent>
						<p class="text-muted-foreground">
							Command-line interface for setting up and managing GURT protocol servers with ease.
						</p>
					</CardContent>
				</Card>
			</div>
		</div>
	</section>

	<!-- Code Examples -->
	<section class="bg-muted/30 px-4 py-20">
		<div class="container mx-auto max-w-6xl">
			<div class="mb-16 text-center">
				<h2 class="font-gurted mb-4 text-4xl font-bold md:text-5xl">See It In Action</h2>
				<p class="text-muted-foreground text-xl">
					An example of a simple GURT site
				</p>
			</div>

			<div class="grid gap-8 md:grid-cols-2">
				<!-- HTML Example -->
				<Card>
					<CardHeader>
						<CardTitle>HTML</CardTitle>
						<CardDescription>HTML with utility-first styling</CardDescription>
					</CardHeader>
					<CardContent>
						<pre class="bg-muted text-foreground overflow-x-auto rounded-lg p-4 text-sm"><code
								class="language-html"
								>{`<head>
    <title>My Gurt Site</title>
    <icon src="gurt://example.real/icon.png">
</head>

<body>
    <h1 style="text-3xl font-bold text-center">
        Welcome to Gurted!
    </h1>
    <div style="flex flex-col gap-4 p-4 bg-[#f8fafc]">
        <p style="text-lg text-[#64748b]">
            The future of web development
        </p>
    </div>
</body>`}</code
							></pre>
					</CardContent>
				</Card>

				<!-- Lua Example -->
				<Card>
					<CardHeader>
						<CardTitle>Lua</CardTitle>
						<CardDescription>Dynamic content with Lua scripting</CardDescription>
					</CardHeader>
					<CardContent>
						<pre class="bg-muted text-foreground overflow-x-auto rounded-lg p-4 text-sm"><code class="language-lua">{`<script>
local heading = gurt.select('h1')
heading:text('Dynamic Content!')

local new_div = gurt.create('div', {
    style = 'bg-blue-500 p-4 rounded'
})

new_div.text = 'Created with Lua!'
gurt.select('body'):append(new_div)

gurt.select('button'):on('click', function()
    trace.log('Button clicked!')
end)
</script>`}</code></pre>
					</CardContent>
				</Card>
			</div>
		</div>
	</section>

	<!-- Downloads Section -->
	<section class="bg-muted/30 px-4 py-10">
		<div class="container mx-auto max-w-4xl text-center">
			<h2 class="font-gurted mb-6 text-4xl font-bold md:text-5xl">Get Started Today</h2>

			<div class="mb-8 grid gap-6 md:grid-cols-2 max-w-2xl mx-auto">
				<Card class="bg-card border-border/50">
					<CardHeader>
						<CardTitle>1. Download</CardTitle>
						<CardDescription>Get the Flumi wayfinder for your platform</CardDescription>
					</CardHeader>
					<CardContent>
						<Button class="w-full" href="/download">
							<Download class="h-4 w-4" />
							Download
						</Button>
					</CardContent>
				</Card>

				<Card class="bg-card border-border/50">
					<CardHeader>
						<CardTitle>2. Start Building</CardTitle>
						<CardDescription>Create your first GURT site</CardDescription>
					</CardHeader>
					<CardContent>
						<Button variant="outline" class="w-full" href="https://docs.gurted.com">
							<ExternalLink class="h-4 w-4" />
							Documentation
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

	code {
		font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
	}

	pre {
		font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
		line-height: 1.4;
	}
</style>
