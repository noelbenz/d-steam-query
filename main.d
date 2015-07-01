
import io = std.stdio;
import std.socket;
import std.string;
import std.datetime;
import core.thread : Thread;

/// Requests the current thread to sleep for <ms> milliseconds.
private void sleepms(int ms)
{
	Thread.sleep(dur!("msecs")(ms));
}

/// Returns the time in <ms> milliseconds
private SysTime timeInMs(int ms)
{
	return Clock.currTime() + dur!("msecs")(ms);
}

/// Returns true if the current time is past the given time, false otherwise.
private bool pastTime(SysTime time)
{
	return Clock.currTime() > time;
}

// Protocol: https://developer.valvesoftware.com/wiki/Master_Server_Query_Protocol

enum Region
{
	usEastCoast = 0,
	usWestCoast = 1,
	southAmerica = 2,
	europe = 3,
	asia = 4,
	australia = 5,
	middleEast = 6,
	africa = 7,
	
	world = 255,
}

struct Query
{
	Region region;
	string ip;
	string filter;
}


struct IPAddress
{
	union
	{
		ubyte[4] bytes;
		uint integer;
		struct
		{
			ubyte a;
			ubyte b;
			ubyte c;
			ubyte d;
		}
	}
	
	ushort port;
	
	/// Returns the first byte of the address as an integer.
	@property int ai(){ return cast(int)a; }
	/// Returns the second byte of the address as an integer.
	@property int bi(){ return cast(int)b; }
	/// Returns the third byte of the address as an integer.
	@property int ci(){ return cast(int)c; }
	/// Returns the fourth byte of the address as an integer.
	@property int di(){ return cast(int)d; }
	
	/// Returns the port as an integer.
	@property int porti(){ return cast(int)port; }
}


class MasterServerQuery
{
	Socket socket;
	
	ubyte[] currentQueryData;
	
	/// Number of seconds to wait on data before making another attempt
	int timeoutDuration = 3;
	/// Number of attempts made to query the master server before exiting
	int maxAttempts = 4;
	
	/// Buffer for received network data.
	ubyte[2048] buffer;
	/// Slice from buffer that has been written to
	ubyte[] bufferSlice;
	
	void delegate(IPAddress) onReceiveIP;
	
	this()
	{
		auto addr = new InternetAddress("hl2master.steampowered.com", 27011);
		socket = new UdpSocket();
		socket.connect(addr);
		socket.blocking = false;
	}
	
	/// Start's a server query
	void query(Query query)
	{
		// 1 byte message type
		// 1 byte region code
		// n+1 bytes string (append null-terminator)
		// n+1 bytes string (append null-terminator)
		int size = 1+1+(query.ip.length+1)+(query.filter.length+1);
		ubyte[] data = new ubyte[size];
		
		ubyte[] slice = data;
		
		// message type
		slice[0] = 0x31;
		slice = slice[1..$];
		
		// region
		slice[0] = cast(ubyte)query.region;
		slice = slice[1..$];
		
		// ip
		slice[0..query.ip.length] = cast(ubyte[])query.ip;
		slice[query.ip.length] = 0;
		slice = slice[query.ip.length+1..$];
		
		// filter
		slice[0..query.filter.length] = cast(ubyte[])query.filter;
		slice[query.filter.length] = 0;
		slice = slice[query.filter.length+1..$];
		
		currentQueryData = data;
		socket.send(data);
		
		bool success = false;
		for(int i = 0; i < maxAttempts; i++)
		{
			if(wait())
			{
				success = true;
				break;
			}
		}
		
		if(!success)
			throw new Exception("Connection timed out.");
		
		process();
		
	}
	
	/// Waits for a response until it times out.
	/// Return's true if a response was received and false if a timeout occurs.
	private bool wait()
	{
		auto timeout = timeInMs(timeoutDuration*1000);
		while(!pastTime(timeout))
		{
			int bytesRead = socket.receive(buffer);
			if(bytesRead > 0)
			{
				bufferSlice = buffer[0..bytesRead];
				return true;
			}
			sleepms(25);
		}
		
		return false;
	}

	void process()
	{
		io.writeln(bufferSlice);
	}
}

void main()
{
	
	MasterServerQuery msq = new MasterServerQuery();
	Query query;
	query.region = Region.world;
	query.ip = "0.0.0.0:0";
	query.filter = "";
	
	msq.query(query);
	
	/*
	ubyte[2048] data;
	
	ubyte[13] query = [0x31, 0xFF, 0x30, 0x2E, 0x30, 0x2E, 0x30, 0x2E, 0x30, 0x3A, 0x30, 0x00, 0x00];
	socket.send(query);
	
	while(true)
	{
		int i = socket.receive(data);
		if(i > 0)
		{
			process(data[0..i]);
		}
	}
	*/
}
