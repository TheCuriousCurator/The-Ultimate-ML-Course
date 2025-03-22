distributed training APIs offered by PyTorch
- torch.distributed, 
- torch.multiprocessing 
- torch.utils.data.distributed.DistributedSampler 

that make distributed training look easy.

Automatic Mixed Precision (AMP) tools
- torch.cuda.amp.autocast 
- torch.cuda.amp.GradScaler 

to reduce the memory footprint while training deep learning models faster.

Libraries such as Horovod, DeepSpeed, and PyTorch Lightning provide sleek APIs to facilitate distributed training of PyTorch models.

Following command shows us live GPU utilization metrics every 0.1 seconds.
`watch -n0.1 nvidia-smi`