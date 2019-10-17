import vibe.appmain;
import vibe.core.file;
import vibe.core.log;
import vibe.core.path;
import vibe.db.mongo.mongo;
import vibe.http.fileserver;
import vibe.http.router;
import vibe.http.server;

import std.exception;

import std.algorithm.iteration : sum;
import std.array;
import std.conv : to;
import std.digest.sha;
import std.range;

enum baseUrl = "https://127.0.0.1";
enum uploadsDir = "./uploads";

MongoDatabase db;
MongoCollection uploadsColl;

string randomHash()
{
	import std.base64 : Base64URL;
	import std.random : rndGen, uniform;

	immutable int length = 5;

	while (true)
	{
		immutable int number = uniform(int.min, int.max, rndGen());
		auto result = Base64URL.encode(sha512Of((cast(ubyte*)&number)[0 .. 8]));

		while (result.length < length)
			result ~= result;			

		// Check if id already exists
		string[string] query = ["directory" : (cast(string) result[0 .. length].idup)];
		if (uploadsColl.findOne(query) == Bson(null))
			return cast(string) result[0 .. length].idup;
	}
}

void uploadFile(scope HTTPServerRequest req, scope HTTPServerResponse res)
{
	auto pf = "file" in req.files;
	enforce(pf !is null, "No file uploaded!");
	
	// Generate unique id
	immutable string newDirName = randomHash();
	immutable string urlPath = newDirName ~ "/" ~ to!string(pf.filename);
	immutable NativePath newDirPath = NativePath(uploadsDir) ~ newDirName;
	immutable NativePath newPath =  newDirPath ~ pf.filename;

	logInfo("Path: %s", newPath);

	try createDirectory(newDirPath);
	catch (Exception e) {
		logWarn("Directory already exists", newPath);
	}

	try moveFile(pf.tempPath, newPath);
	catch (Exception e) {
		copyFile(pf.tempPath, newPath);
	}

	uploadsColl.insert(["name": to!string(pf.filename), "directory": newDirName]);

	res.writeBody("{\"url\": \"" ~ baseUrl ~ "/" ~ urlPath ~ "\"}", "text/json");
}

shared static this()
{
	// Setup db
	db = connectMongoDB("localhost").getDatabase("uploader");
	uploadsColl = db["uploads"];

	// Setup FS
	if (!existsFile(NativePath(uploadsDir)))
		createDirectory(NativePath(uploadsDir));

	auto router = new URLRouter;
	router.get("/", staticTemplate!"upload_form.dt");
	router.post("/upload", &uploadFile);
	router.get("*", serveStaticFiles(uploadsDir));

	auto settings = new HTTPServerSettings;
	settings.port = 9021;
	settings.bindAddresses = ["::1", "127.0.0.1"];
	listenHTTP(settings, router);
}