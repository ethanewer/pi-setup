import grpc
from concurrent import futures

import echo_pb2 as pb2
import echo_pb2_grpc as pb2g


class Greeter(pb2g.GreetServiceServicer):
    def Greet(self, request, context):
        return pb2.GreetResponse(message="HELLO, " + request.name.upper())


if __name__ == "__main__":
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=4))
    pb2g.add_GreetServiceServicer_to_server(Greeter(), server)
    server.add_insecure_port("127.0.0.1:50051")
    server.start()
    print("GreetService listening on 127.0.0.1:50051", flush=True)
    server.wait_for_termination()